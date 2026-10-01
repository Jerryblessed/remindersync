import os
import time
import sqlite3
import json
from datetime import datetime, timedelta
from flask import Flask, request, jsonify
from flask_cors import CORS
from werkzeug.security import generate_password_hash, check_password_hash
from google import genai
from google.genai import types

app = Flask(__name__)
CORS(app)

# CONFIGURATION
GEMINI_API_KEY ="AQ.Ab8RN6L38tUETkvV4SAi0rlRfhjOSsCvSlmuBI8BhNbiU_pqiQ"
ADMIN_KEY = os.environ.get("ADMIN_KEY", "MyFallbackKey2026!")
client = genai.Client(api_key=GEMINI_API_KEY, http_options={'api_version': 'v1alpha'})

# DATABASE SETUP
def init_db():
    conn = sqlite3.connect('reminders.db')
    c = conn.cursor()
    
    # Users table
    c.execute('''CREATE TABLE IF NOT EXISTS users 
                 (id INTEGER PRIMARY KEY AUTOINCREMENT, 
                  email TEXT UNIQUE, 
                  password TEXT, 
                  trials INTEGER DEFAULT 5, 
                  tier TEXT DEFAULT 'free',
                  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)''')
    
    # Reminders table
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

# === AUTH ROUTES ===

@app.route('/auth/register', methods=['POST'])
def register():
    data = request.json
    email = data.get('email')
    password = generate_password_hash(data.get('password'))
    
    try:
        conn = sqlite3.connect('reminders.db')
        c = conn.cursor()
        c.execute("INSERT INTO users (email, password) VALUES (?, ?)", (email, password))
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
    except Exception as e:
        return jsonify({'success': False, 'message': 'User already exists'}), 400

@app.route('/auth/login', methods=['POST'])
def login():
    data = request.json
    conn = sqlite3.connect('reminders.db')
    conn.row_factory = sqlite3.Row
    c = conn.cursor()
    user = c.execute("SELECT * FROM users WHERE email = ?", (data.get('email'),)).fetchone()
    conn.close()
    
    if user and check_password_hash(user['password'], data.get('password')):
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

# === REMINDERS ROUTES ===

@app.route('/reminders/<user_id>', methods=['GET'])
def get_reminders(user_id):
    conn = sqlite3.connect('reminders.db')
    conn.row_factory = sqlite3.Row
    c = conn.cursor()
    
    reminders = c.execute(
        "SELECT * FROM reminders WHERE user_id = ? ORDER BY datetime ASC",
        (user_id,)
    ).fetchall()
    
    conn.close()
    
    return jsonify({
        'reminders': [dict(r) for r in reminders]
    })

@app.route('/reminders/<user_id>', methods=['POST'])
def create_reminder(user_id):
    data = request.json
    
    conn = sqlite3.connect('reminders.db')
    c = conn.cursor()
    
    c.execute('''INSERT INTO reminders 
                 (id, user_id, title, description, datetime, recurring_pattern, is_completed)
                 VALUES (?, ?, ?, ?, ?, ?, ?)''',
              (data['id'], user_id, data['title'], data.get('description'), 
               data['datetime'], data.get('recurring_pattern'), data.get('is_completed', 0)))
    
    conn.commit()
    conn.close()
    
    return jsonify({'success': True, 'message': 'Reminder created'})

@app.route('/reminders/<user_id>/<reminder_id>', methods=['PUT'])
def update_reminder(user_id, reminder_id):
    data = request.json
    
    conn = sqlite3.connect('reminders.db')
    c = conn.cursor()
    
    c.execute('''UPDATE reminders 
                 SET title = ?, description = ?, datetime = ?, 
                     recurring_pattern = ?, is_completed = ?, updated_at = CURRENT_TIMESTAMP
                 WHERE id = ? AND user_id = ?''',
              (data['title'], data.get('description'), data['datetime'],
               data.get('recurring_pattern'), data.get('is_completed', 0), 
               reminder_id, user_id))
    
    conn.commit()
    conn.close()
    
    return jsonify({'success': True, 'message': 'Reminder updated'})

@app.route('/reminders/<user_id>/<reminder_id>', methods=['DELETE'])
def delete_reminder(user_id, reminder_id):
    conn = sqlite3.connect('reminders.db')
    c = conn.cursor()
    
    c.execute("DELETE FROM reminders WHERE id = ? AND user_id = ?", 
              (reminder_id, user_id))
    
    conn.commit()
    conn.close()
    
    return jsonify({'success': True, 'message': 'Reminder deleted'})

# === AI PARSING ===

@app.route('/ai/parse-reminder', methods=['POST'])
def parse_reminder():
    data = request.json
    text = data.get('text', '')
    user_id = data.get('user_id')
    
    # Check if user has credits
    conn = sqlite3.connect('reminders.db')
    c = conn.cursor()
    user = c.execute("SELECT trials FROM users WHERE id = ?", (user_id,)).fetchone()
    
    if not user or user[0] <= 0:
        conn.close()
        return jsonify({'success': False, 'message': 'No credits remaining'}), 403
    
    # Deduct credit
    c.execute("UPDATE users SET trials = trials - 1 WHERE id = ?", (user_id,))
    conn.commit()
    conn.close()
    
    # Use Gemini 3 Flash with structured output
    try:
        response = client.models.generate_content(
            model="gemini-3-flash-preview",
            contents=f"""Parse this reminder request into structured data: "{text}"
            
Extract:
- title: concise task name
- description: optional details
- datetime: ISO 8601 format (use current date/time as base)
- recurring: if mentioned, include type (hourly/daily/weekly/monthly), interval, and days_of_week (1-7 for Mon-Sun)

Current datetime: {datetime.now().isoformat()}

Return ONLY valid JSON matching this schema.""",
            config=types.GenerateContentConfig(
                thinking_config=types.ThinkingConfig(thinking_level="medium"),
                response_mime_type="application/json",
                response_json_schema={
                    "type": "object",
                    "properties": {
                        "title": {"type": "string"},
                        "description": {"type": ["string", "null"]},
                        "datetime": {"type": "string"},
                        "recurring": {
                            "type": ["object", "null"],
                            "properties": {
                                "type": {"type": "string"},
                                "interval": {"type": "integer"},
                                "days_of_week": {"type": ["array", "null"], "items": {"type": "integer"}}
                            }
                        }
                    },
                    "required": ["title", "datetime"]
                }
            )
        )
        
        parsed_data = json.loads(response.text)
        return jsonify({'success': True, 'data': parsed_data})
        
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500

# === SYNC ENDPOINT ===

@app.route('/sync/<user_id>', methods=['POST'])
def sync_reminders(user_id):
    """
    Sync reminders across devices - implements proper conflict resolution
    """
    data = request.json
    local_reminders = data.get('reminders', [])
    
    conn = sqlite3.connect('reminders.db')
    conn.row_factory = sqlite3.Row
    c = conn.cursor()
    
    # Get server reminders
    server_reminders = c.execute(
        "SELECT * FROM reminders WHERE user_id = ?", (user_id,)
    ).fetchall()
    
    server_dict = {r['id']: dict(r) for r in server_reminders}
    local_dict = {r['id']: r for r in local_reminders}
    
    # Merge logic: server wins on conflicts (last write wins by updated_at)
    to_update = []
    to_insert = []
    
    for local_id, local_rem in local_dict.items():
        if local_id in server_dict:
            # Compare updated_at timestamps
            server_updated = datetime.fromisoformat(server_dict[local_id]['updated_at'])
            local_updated = datetime.fromisoformat(local_rem['updated_at'])
            
            if local_updated > server_updated:
                to_update.append(local_rem)
        else:
            to_insert.append(local_rem)
    
    # Apply updates
    for rem in to_update:
        c.execute('''UPDATE reminders 
                     SET title = ?, description = ?, datetime = ?, 
                         recurring_pattern = ?, is_completed = ?, 
                         updated_at = ?, synced_at = CURRENT_TIMESTAMP
                     WHERE id = ?''',
                  (rem['title'], rem.get('description'), rem['datetime'],
                   rem.get('recurring_pattern'), rem.get('is_completed', 0),
                   rem['updated_at'], rem['id']))
    
    # Apply inserts
    for rem in to_insert:
        c.execute('''INSERT INTO reminders 
                     (id, user_id, title, description, datetime, recurring_pattern, is_completed, created_at, updated_at)
                     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
                  (rem['id'], user_id, rem['title'], rem.get('description'),
                   rem['datetime'], rem.get('recurring_pattern'), rem.get('is_completed', 0),
                   rem['created_at'], rem['updated_at']))
    
    conn.commit()
    
    # Return updated server state
    all_reminders = c.execute(
        "SELECT * FROM reminders WHERE user_id = ? ORDER BY datetime ASC",
        (user_id,)
    ).fetchall()
    
    conn.close()
    
    return jsonify({
        'success': True,
        'reminders': [dict(r) for r in all_reminders]
    })

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000)