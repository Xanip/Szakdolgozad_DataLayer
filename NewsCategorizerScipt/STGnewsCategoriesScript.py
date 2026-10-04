import pyodbc
import ollama
import time
import os
from dotenv import load_dotenv

# .env fájl betöltése
load_dotenv()

conn_str_rawstaging = os.getenv("DB_CONNECTION_RAWSTAGING")
conn_str_dimfact = os.getenv("DB_CONNECTION_DIMFACT")
model = os.getenv("OLLAMA_MODEL")

if not conn_str_rawstaging or not conn_str_dimfact:
    raise ValueError("A DB_CONNECTION környezeti változó nincs beállítva. Kérlek, ellenőrizd a .env fájlt.")

if not model:
    raise ValueError("A OLLAMA_MODEL környezeti változó nincs beállítva. Kérlek, ellenőrizd a .env fájlt.")

# 1. ADATOK LEKÉRÉSE (Read-only)
print("Csatlakozás az adatbázishoz...")
dimfact_conn = pyodbc.connect(conn_str_dimfact)
# conn = pyodbc.connect('Driver={SQL Server};'
#                       'Server=DESKTOP-VEDC4M9\SQLEXPRESS01;'
#                       'Database=Onvezetett_laboratorium;'
#                       'Trusted_Connection=yes;')
dimdact_cursor = dimfact_conn.cursor()

# Olvasuk a kategóriákat a DimCategory táblából, hogy biztosan naprakészek legyenek
query = """
    SELECT CategoryName FROM DimCategory
"""
dimdact_cursor.execute(query)
allowed_categories_db = [row.CategoryName for row in dimdact_cursor.fetchall()]
print(f"Adatbázisból lekért kategóriák: {allowed_categories_db}")
categories_string = ", ".join(allowed_categories_db)

dimdact_cursor.close()
dimfact_conn.close()  # Bezárjuk a DimFact adatbázis kapcsolatot, mert már nincs rá szükség

raw_conn = pyodbc.connect(conn_str_rawstaging)
raw_cursor = raw_conn.cursor()

# Hírek lekérdezése a RAWnews táblából, ahol ProcessedFlag = 0 (még nem feldolgozott cikkek)
query = """
    SELECT r.ArticleID, r.Title, r.Description, r.Content 
    FROM RAWnews r
    WHERE r.ProcessedFlag = 0
"""
raw_cursor.execute(query)
articles = raw_cursor.fetchall()
total_articles = len(articles)

if total_articles == 0:
    print("Nincs feldolgozandó cikk az adatbázisban (vagy mindnek 1-es a ProcessedFlag-je).")
    exit()

print(f"\n--- TESZT INDUL: {total_articles} cikk feldolgozása ---")

# -----------------------------------------------------
# 2. AI FELDOLGOZÁS ÉS IDŐMÉRÉS
results = []
start_time = time.time() # Stopper elindítása

for i, article in enumerate(articles, 1):
    article_id = article.ArticleID
    title = article.Title if article.Title else ""
    description = article.Description if article.Description else ""
    
    raw_content = article.Content if article.Content else ""
    clean_content = raw_content.split('[+')[0].strip()

    print(f"[{i}/{total_articles}] Generálás: {title[:50]}...")

    prompt = f"""You are a highly accurate financial and political news classifier.
    Classify the given news article into EXACTLY ONE of the following categories: {categories_string}.
    Rules:
    - Respond with the category name ONLY.
    - Do not add punctuation, explanations, or any other words.
    - You MUST choose from the provided list.

    EXAMPLE 1:
    Title: US and UK launch strikes against Houthi targets in Yemen
    Description: The military action is in response to attacks on international shipping.
    Content: Fighter jets targeted radar systems and drone storage facilities...
    Category: Military Conflict

    EXAMPLE 2:
    Title: Apple shares hit record high ahead of earnings report
    Description: Investors are optimistic about the new iPhone sales.
    Content: Tech giant Apple saw its stock surge by 3% on Wall Street today...
    Category: Stock Market

    EXAMPLE 3:
    Title: Senate passes controversial immigration bill
    Description: The new policy will drastically change border control procedures.
    Content: After hours of debate, lawmakers voted in favor of the new legislation...
    Category: Global Politics

    NOW CLASSIFY THIS ARTICLE:
    Title: {title}
    Description: {description}
    Content: {clean_content}
    Category: """

    # Ollama hívás qwen2.5:1.5b modellel
    response = ollama.chat(
        #model='qwen2.5:1.5b', 
        model=model,
        messages=[{'role': 'user', 'content': prompt}],
        options={'temperature': 0.0}
    )
    
    ai_answer = response['message']['content'].strip()
    if ai_answer.endswith('.'): ai_answer = ai_answer[:-1]
    
    final_category = ai_answer if ai_answer in allowed_categories_db else "Unknown (Other)"
    
    results.append((article_id, title, final_category))

end_time = time.time()
elapsed_time = end_time - start_time

# -----------------------------------------------------
# 3. EREDMÉNYEK KIÍRÁSA Adatbázisba (Write-only)
for res in results:
    article_id, title, category = res
    insert_query = """
        INSERT INTO STGnewsCategory (RAWArticleID, GeneratedCategory)
        VALUES (?, ?)
    """
    raw_cursor.execute(insert_query, (article_id, category))
raw_conn.commit()

print("Adatok sikeresen elmentve az adatbázisba!")

# Kapcsolat lezárása
raw_cursor.close()
raw_conn.close()

# -----------------------------------------------------
# 4. EREDMÉNYEK KIÍRÁSA A KONZOLRA
print("\n" + "="*50)
print(" VÉGLEGES EREDMÉNYEK ".center(50, "="))
print("="*50)

for res in results:
    article_id_str = str(res[0]).ljust(4) # Hogy szépen egy oszlopban legyenek
    category_str = res[2].ljust(20)
    title_str = res[1][:120] + "..." if len(res[1]) > 120 else res[1]
    
    print(f"ID: {article_id_str} | Kat: {category_str} | Cím: {title_str}")

print("-" * 50)
print(f"Összes futási idő: {elapsed_time:.2f} másodperc.")
print(f"Átlagos idő / cikk: {(elapsed_time / total_articles):.2f} másodperc.")