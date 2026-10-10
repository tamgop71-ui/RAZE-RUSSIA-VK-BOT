-- Optional schema reference for SQLite. The bot creates these tables automatically.
-- This file is provided for documentation; it is not a MySQL import script.
CREATE TABLE roles (user_id INTEGER PRIMARY KEY, role TEXT NOT NULL DEFAULT 'Участник', priority INTEGER NOT NULL DEFAULT 0, granted_by INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL);
CREATE TABLE superusers (user_id INTEGER PRIMARY KEY, granted_by INTEGER NOT NULL, created_at TEXT NOT NULL);
CREATE TABLE warnings (id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER NOT NULL, actor_id INTEGER NOT NULL, reason TEXT NOT NULL, created_at TEXT NOT NULL, active INTEGER NOT NULL DEFAULT 1);
CREATE TABLE mutes (user_id INTEGER PRIMARY KEY, actor_id INTEGER NOT NULL, reason TEXT NOT NULL, expires_at INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL);
CREATE TABLE bans (user_id INTEGER PRIMARY KEY, actor_id INTEGER NOT NULL, reason TEXT NOT NULL, expires_at INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL);
CREATE TABLE reports (id INTEGER PRIMARY KEY AUTOINCREMENT, peer_id INTEGER NOT NULL, user_id INTEGER NOT NULL, message TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'open', assigned_to INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL, closed_at TEXT);
CREATE TABLE nicknames (user_id INTEGER PRIMARY KEY, nickname TEXT NOT NULL, updated_by INTEGER NOT NULL, updated_at TEXT NOT NULL);
CREATE TABLE audit_log (id INTEGER PRIMARY KEY AUTOINCREMENT, peer_id INTEGER NOT NULL DEFAULT 0, actor_id INTEGER NOT NULL, action TEXT NOT NULL, target_id INTEGER NOT NULL DEFAULT 0, details TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL);
CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
