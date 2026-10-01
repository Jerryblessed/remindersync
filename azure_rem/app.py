import os
import time
import sqlite3
import json
import requests
from datetime import datetime, timedelta
from flask import Flask, request, jsonify
from flask_cors import CORS
from werkzeug.security import generate_password_hash, check_password_hash

app = Flask(__name__)
CORS(app)

# ==========================================
# CONFIGURATION & ENVIRONMENT
# ==========================================
DB_PATH = 'reminders.db'
ADMIN_KEY = os.environ.get("ADMIN_KEY", "MyFallbackKey2026!")

# Microsoft Foundry Configuration (gpt-5.4-nano)
AI_ENDPOINT = os.environ.get(
    "AI_ENDPOINT",
    "https://opejeremiah-2939-resource.services.ai.azure.com/openai/v1/chat/completions"
)
AI_KEY = os.environ.get(
    "AI_KEY",
    "5rU3LmcHk8WjNdiyJ30vbmsTNGuHhFfe9Ln5hXz6DtkrqOYWSB7IJQQJ99CEAC1i4TkXJ3w3AAAAACOG5h7l"
)
AI_MODEL = "gpt-5.4-nano"

# ==========================================
# BULLETPROOF DATABASE CONNECTION
# ==========================================
def get_db():
    conn = sqlite3.connect(DB_PATH, timeout=30.0)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL;")
    conn.execute("PRAGMA synchronous=NORMAL;")
    return conn

def init_db():
    conn = get_db()
    c = conn.cursor()
    c.execute('''CREATE TABLE IF NOT EXISTS users 
                 (id INTEGER PRIMARY KEY AUTOINCREMENT, 
                  email TEXT UNIQUE, 
                  password TEXT, 
                  trials INTEGER DEFAULT 5, 
                  tier TEXT DEFAULT 'free',
                  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)''')
    
    c.execute('''CREATE TABLE IF NOT EXISTS reminders 
                 (id TEXT PRIMARY KEY, 
                  user_id INTEGER, 
                  title TEXT NOT NULL,
                  description TEXT,
                  datetime TIMESTAMP NOT NULL,
                  recurring_pattern TEXT,
                  is_completed INTEGER DEFAULT 0,
                  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                  synced_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                  FOREIGN KEY (user_id) REFERENCES users(id))''')
    conn.commit()
    conn.close()

init_db()

# ==========================================
# AI CALLER (Microsoft Foundry gpt-5.4-nano)
# ==========================================
def call_gpt_nano(prompt, system_instruction="You are a natural language thought capture and reminder scheduling assistant."):
    headers = {
        "Content-Type": "application/json",
        "api-key": AI_KEY,
        "Authorization": f"Bearer {AI_KEY}"
    }

    target_url = AI_ENDPOINT
    if target_url.endswith("/responses"):
        target_url = target_url.replace("/responses", "/chat/completions")

    payload = {
        "model": AI_MODEL,
        "messages": [
            {"role": "system", "content": system_instruction},
            {"role": "user", "content": prompt}
        ],
        "temperature": 0.3
    }

    try:
        res = requests.post(target_url, headers=headers, json=payload, timeout=25)
        if res.status_code == 200:
            return res.json()['choices'][0]['message']['content'].strip()
        else:
            return None
    except Exception:
        return None

# ==========================================
# AUTH ROUTES
# ==========================================
@app.route('/auth/register', methods=['POST'])
def register():
    data = request.json or {}
    email = data.get('email', '').strip().lower()
    password = data.get('password', '')
    
    if not email or not password:
        return jsonify({'success': False, 'message': 'Email and password required'}), 400

    try:
        conn = get_db()
        c = conn.cursor()
        c.execute("INSERT INTO users (email, password) VALUES (?, ?)", 
                  (email, generate_password_hash(password)))
        user_id = c.lastrowid
        conn.commit()
        conn.close()
        
        return jsonify({
            'success': True, 
            'message': 'User registered',
            'user': {
                'user_id': str(user_id),
                'email': email,
                'trials_remaining': 5,
                'tier': 'free'
            }
        })
    except sqlite3.IntegrityError:
        return jsonify({'success': False, 'message': 'User already exists'}), 400
    except Exception as e:
        return jsonify({'success': False, 'message': f'Registration failed: {str(e)}'}), 500

@app.route('/auth/login', methods=['POST'])
def login():
    data = request.json or {}
    email = data.get('email', '').strip().lower()
    password = data.get('password', '')
    
    conn = get_db()
    c = conn.cursor()
    user = c.execute("SELECT * FROM users WHERE email = ?", (email,)).fetchone()
    conn.close()
    
    if user and check_password_hash(user['password'], password):
        return jsonify({
            'success': True, 
            'user': {
                'user_id': str(user['id']), 
                'email': user['email'], 
                'trials_remaining': user['trials'],
                'tier': user['tier']
            }
        })
    return jsonify({'success': False, 'message': 'Invalid credentials'}), 401

# ==========================================
# REMINDER CRUD ROUTES
# ==========================================
@app.route('/reminders/<user_id>', methods=['GET'])
def get_reminders(user_id):
    conn = get_db()
    c = conn.cursor()
    reminders = c.execute("SELECT * FROM reminders WHERE user_id = ? ORDER BY datetime ASC", (user_id,)).fetchall()
    conn.close()
    return jsonify({'reminders': [dict(r) for r in reminders]})

@app.route('/reminders/<user_id>', methods=['POST'])
def create_reminder(user_id):
    data = request.json or {}
    conn = get_db()
    c = conn.cursor()
    c.execute('''INSERT INTO reminders 
                 (id, user_id, title, description, datetime, recurring_pattern, is_completed)
                 VALUES (?, ?, ?, ?, ?, ?, ?)''',
              (data.get('id', str(uuid.uuid4())), user_id, data.get('title'), data.get('description', ''), 
               data.get('datetime', datetime.utcnow().isoformat()), data.get('recurring_pattern'), data.get('is_completed', 0)))
    conn.commit()
    conn.close()
    return jsonify({'success': True, 'message': 'Reminder created'})

@app.route('/reminders/<user_id>/<reminder_id>', methods=['PUT'])
def update_reminder(user_id, reminder_id):
    data = request.json or {}
    conn = get_db()
    c = conn.cursor()
    c.execute('''UPDATE reminders 
                 SET title = ?, description = ?, datetime = ?, 
                     recurring_pattern = ?, is_completed = ?, updated_at = CURRENT_TIMESTAMP
                 WHERE id = ? AND user_id = ?''',
              (data.get('title'), data.get('description'), data.get('datetime'),
               data.get('recurring_pattern'), data.get('is_completed', 0), 
               reminder_id, user_id))
    conn.commit()
    conn.close()
    return jsonify({'success': True, 'message': 'Reminder updated'})

@app.route('/reminders/<user_id>/<reminder_id>', methods=['DELETE'])
def delete_reminder(user_id, reminder_id):
    conn = get_db()
    c = conn.cursor()
    c.execute("DELETE FROM reminders WHERE id = ? AND user_id = ?", (reminder_id, user_id))
    conn.commit()
    conn.close()
    return jsonify({'success': True, 'message': 'Reminder deleted'})

# ==========================================
# AI NATURAL LANGUAGE PARSER
# ==========================================
@app.route('/ai/parse-reminder', methods=['POST'])
def parse_reminder():
    data = request.json or {}
    text = data.get('text', '')
    user_id = data.get('user_id')
    
    conn = get_db()
    c = conn.cursor()
    user = c.execute("SELECT trials, tier FROM users WHERE id = ?", (user_id,)).fetchone()
    
    if not user:
        conn.close()
        return jsonify({'success': False, 'message': 'User not found'}), 404
        
    if user['tier'] == 'free' and user['trials'] <= 0:
        conn.close()
        return jsonify({'success': False, 'message': 'No credits remaining'}), 403
        
    if user['trials'] > 0:
        c.execute("UPDATE users SET trials = trials - 1 WHERE id = ?", (user_id,))
        conn.commit()
    conn.close()
    
    now_iso = datetime.utcnow().isoformat()
    prompt = f"""
    Parse this natural language thought into a structured reminder: "{text}"
    Current Datetime base: {now_iso}
    
    Return ONLY a JSON object:
    {{
        "title": "Concise task summary",
        "description": "Any Action Snippets, URLs, or notes",
        "datetime": "ISO 8601 string",
        "recurring": null
    }}
    """
    
    raw = call_gpt_nano(prompt, system_instruction="Output strictly valid JSON.")
    try:
        clean = raw.replace("```json", "").replace("```", "").strip() if raw else ""
        parsed = json.loads(clean)
        return jsonify({'success': True, 'data': parsed})
    except Exception:
        # Fallback if unparseable
        return jsonify({
            'success': True,
            'data': {
                'title': text[:40],
                'description': text,
                'datetime': (datetime.utcnow() + timedelta(hours=2)).isoformat(),
                'recurring': None
            }
        })

# ==========================================
# CLOUD SYNC WITH CONFLICT RESOLUTION
# ==========================================
@app.route('/sync/<user_id>', methods=['POST'])
def sync_reminders(user_id):
    data = request.json or {}
    local_reminders = data.get('reminders', [])
    
    conn = get_db()
    c = conn.cursor()
    
    server_reminders = c.execute("SELECT * FROM reminders WHERE user_id = ?", (user_id,)).fetchall()
    server_dict = {r['id']: dict(r) for r in server_reminders}
    local_dict = {r['id']: r for r in local_reminders}
    
    # Conflict resolution: Last write wins
    for local_id, local_rem in local_dict.items():
        if local_id in server_dict:
            try:
                server_up = datetime.fromisoformat(server_dict[local_id]['updated_at'])
                local_up = datetime.fromisoformat(local_rem.get('updated_at', ''))
                if local_up > server_up:
                    c.execute('''UPDATE reminders 
                                 SET title = ?, description = ?, datetime = ?, 
                                     recurring_pattern = ?, is_completed = ?, 
                                     updated_at = ?, synced_at = CURRENT_TIMESTAMP
                                 WHERE id = ?''',
                              (local_rem.get('title'), local_rem.get('description'), local_rem.get('datetime'),
                               local_rem.get('recurring_pattern'), local_rem.get('is_completed', 0),
                               local_rem.get('updated_at'), local_id))
            except Exception:
                pass
        else:
            c.execute('''INSERT INTO reminders 
                         (id, user_id, title, description, datetime, recurring_pattern, is_completed, created_at, updated_at)
                         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
                      (local_rem['id'], user_id, local_rem.get('title'), local_rem.get('description', ''),
                       local_rem.get('datetime', datetime.utcnow().isoformat()), local_rem.get('recurring_pattern'), 
                       local_rem.get('is_completed', 0), local_rem.get('created_at', datetime.utcnow().isoformat()),
                       local_rem.get('updated_at', datetime.utcnow().isoformat())))
                       
    conn.commit()
    all_reminders = c.execute("SELECT * FROM reminders WHERE user_id = ? ORDER BY datetime ASC", (user_id,)).fetchall()
    conn.close()
    
    return jsonify({'success': True, 'reminders': [dict(r) for r in all_reminders]})

# ==========================================
# ADMIN, POLICIES & HEALTH
# ==========================================
@app.route('/admin')
def admin_dashboard():
    if request.args.get('key') != ADMIN_KEY:
        return jsonify({'error': 'Unauthorized'}), 401

    conn = get_db()
    c = conn.cursor()
    users = c.execute("SELECT id, email, tier, trials, created_at FROM users ORDER BY id DESC").fetchall()
    conn.close()

    rows = "".join([f"""
        <tr>
            <td style='padding:12px; border-bottom:1px solid #eee;'>{u['id']}</td>
            <td style='padding:12px; border-bottom:1px solid #eee; font-weight:600;'>{u['email']}</td>
            <td style='padding:12px; border-bottom:1px solid #eee;'>
                <span style='background:#EEF2FF; color:#4F46E5; padding:4px 10px; border-radius:12px; font-size:12px; font-weight:bold;'>
                    {(u['tier'] or 'FREE').upper()}
                </span>
            </td>
            <td style='padding:12px; border-bottom:1px solid #eee;'>{u['trials']}</td>
            <td style='padding:12px; border-bottom:1px solid #eee; color:#64748b;'>{u['created_at']}</td>
        </tr>
    """ for u in users])

    return f"""
    <!DOCTYPE html>
    <html>
    <head>
        <title>ReminderSync AI - Admin Dashboard</title>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
            body {{ font-family: -apple-system, sans-serif; background: #f8fafc; padding: 30px; }}
            .card {{ background: white; border-radius: 16px; box-shadow: 0 4px 6px rgba(0,0,0,0.05); max-width: 800px; margin: auto; overflow: hidden; }}
            .header {{ background: #4F46E5; color: white; padding: 24px; }}
            table {{ width: 100%; border-collapse: collapse; text-align: left; }}
            th {{ background: #f1f5f9; padding: 14px; font-size: 13px; color: #475569; }}
        </style>
    </head>
    <body>
        <div class="card">
            <div class="header">
                <h2 style="margin:0;">ReminderSync AI - Registered Users ({len(users)})</h2>
                <p style="margin:6px 0 0; opacity:0.85; font-size:13px;">Engine: Microsoft Foundry ({AI_MODEL}) | DB: SQLite (WAL Active)</p>
            </div>
            <table>
                <thead>
                    <tr><th>ID</th><th>Email</th><th>Tier</th><th>Trials Left</th><th>Joined</th></tr>
                </thead>
                <tbody>
                    {rows if rows else "<tr><td colspan='5' style='padding:24px; text-align:center;'>No users registered yet.</td></tr>"}
                </tbody>
            </table>
        </div>
    </body>
    </html>
    """

@app.route('/delete-account')
def delete_account_info():
    return """
    <!DOCTYPE html>
    <html>
    <head><meta charset="UTF-8"><title>ReminderSync AI - Delete Account</title></head>
    <body style="font-family:sans-serif; padding:40px; max-width:600px; margin:auto; line-height:1.6; color:#222;">
        <h2>ReminderSync AI - Account & Data Deletion</h2>
        <p>To delete your ReminderSync AI account, scheduled tasks, and Action Snippets, please email <b>support@presentmeapp.xyz</b> with the subject 'Delete Account'.</p>
        <p>Your request will be processed, and all synced reminder data will be permanently removed within 30 days.</p>
    </body>
    </html>
    """

@app.route("/privacy")
def privacy_policy():
    return """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Privacy Policy - ReminderSync AI</title>
        <style>
            body { font-family: -apple-system, sans-serif; line-height: 1.6; max-width: 800px; margin: 0 auto; padding: 30px; color: #222; background: #f8fafc; }
            h1, h2 { color: #4F46E5; }
            .card { background: white; padding: 30px; border-radius: 12px; box-shadow: 0 2px 8px rgba(0,0,0,0.06); }
        </style>
    </head>
    <body>
        <div class="card">
            <h1>Privacy Policy for ReminderSync AI</h1>
            <p><strong>Effective Date:</strong> September 2026</p>
            <p>ReminderSync AI ("we", "our", or "us") provides AI-powered thought capture, reusable action snippets, and cloud synchronization tools.</p>
            <h2>1. Information We Collect</h2>
            <p>• <strong>Personal Information:</strong> Email address for account authentication and multi-device cloud synchronization.</p>
            <p>• <strong>Reminder & Snippet Data:</strong> Task titles, scheduled timestamps, notes, and template text stored for timeline display.</p>
            <p>• <strong>Purchase History:</strong> Tracked via Google Play Billing and RevenueCat to unlock Pro plans and AI parse credits.</p>
            <h2>2. Third-Party Services</h2>
            <p>We integrate with Google Play Services (billing), Microsoft Foundry AI (natural language parsing), and RevenueCat (in-app subscription management).</p>
            <h2>3. Data Deletion & Contact</h2>
            <p>To request permanent deletion of your account and synced reminders, contact us at <strong>support@presentmeapp.xyz</strong>.</p>
        </div>
    </body>
    </html>
    """

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({
        'status': 'healthy',
        'service': 'ReminderSync API',
        'engine': AI_MODEL,
        'timestamp': datetime.utcnow().isoformat()
    })

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000)