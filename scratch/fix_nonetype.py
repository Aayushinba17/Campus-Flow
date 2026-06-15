import os
import re

app_dir = "/home/paarth/development/campus_flow/campus_flow_backend/app"

# Regex patterns to find `.get("key", "default") >=` or `<=` or `<` or `>`
# specifically for ingested_at, timestamp, date, deadline
patterns = [
    (r'\.get\("ingested_at",\s*""\)\s*(>=|>|<=|<)', r'.get("ingested_at") or "") \1'),
    (r'\.get\("date",\s*""\)\s*(>=|>|<=|<)', r'.get("date") or "") \1'),
    (r'\.get\("timestamp",\s*""\)\s*(>=|>|<=|<)', r'.get("timestamp") or "") \1'),
    (r'\.get\("deadline",\s*"9999"\)\s*(>=|>|<=|<)', r'.get("deadline") or "9999") \1'),
]

for root, _, files in os.walk(app_dir):
    for file in files:
        if file.endswith(".py"):
            path = os.path.join(root, file)
            with open(path, "r") as f:
                content = f.read()
            
            new_content = content
            for pat, repl in patterns:
                # We need to prepend the object variable, e.g. `n.get...` -> `(n.get...`
                # So let's match the variable name before `.get`
                # e.g., `n.get("ingested_at", "") >=` -> `(n.get("ingested_at") or "") >=`
                new_content = re.sub(r'(\w+)\.get\("ingested_at",\s*""\)\s*(>=|>|<=|<)', r'(\1.get("ingested_at") or "") \2', new_content)
                new_content = re.sub(r'(\w+)\.get\("date",\s*""\)\s*(>=|>|<=|<)', r'(\1.get("date") or "") \2', new_content)
                new_content = re.sub(r'(\w+)\.get\("timestamp",\s*""\)\s*(>=|>|<=|<)', r'(\1.get("timestamp") or "") \2', new_content)
                new_content = re.sub(r'(\w+)\.get\("deadline",\s*"9999"\)\s*(>=|>|<=|<)', r'(\1.get("deadline") or "9999") \2', new_content)
            
            if new_content != content:
                with open(path, "w") as f:
                    f.write(new_content)
                print(f"Updated {path}")
