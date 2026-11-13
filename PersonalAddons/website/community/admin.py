#!/usr/bin/env python3
"""Local maintenance only. No HTTP administrator endpoint."""
import argparse
import json
from pathlib import Path
import sqlite3
import os

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--database', type=Path, default=Path(os.environ.get('DATA_DIR', '/data')) / 'suggestions.sqlite3')
sub = p.add_subparsers(dest='command', required=True)
remove = sub.add_parser('delete', help='Remove the text of one post; retain the floor number and prevent replay')
remove.add_argument('id', type=int)
backup = sub.add_parser('backup', help='Consistent SQLite backup, including pending WAL writes')
backup.add_argument('destination', type=Path)
args = p.parse_args()
if not args.database.is_file():
    p.error('Database does not exist')
os.umask(0o077)
with sqlite3.connect(args.database) as db:
    if args.command == 'delete':
        cursor = db.execute("UPDATE suggestions SET deleted=1,nickname='',body='' WHERE id=? AND deleted=0", (args.id,))
        print(json.dumps({'deleted': cursor.rowcount == 1, 'id': args.id}))
    else:
        if args.destination.exists():
            p.error('Backup destination must not already exist')
        with sqlite3.connect(args.destination) as output:
            db.backup(output)
        print(json.dumps({'backup_created': True}))
