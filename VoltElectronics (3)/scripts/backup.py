"""Create a consistent SQLite snapshot, including a database currently in use."""
import argparse
import sqlite3
from pathlib import Path

parser=argparse.ArgumentParser()
parser.add_argument('source')
parser.add_argument('destination')
args=parser.parse_args()
if not Path(args.source).is_file():
    parser.error('Source database does not exist')
if Path(args.destination).exists():
    parser.error('Destination exists; use a new backup filename')
Path(args.destination).parent.mkdir(parents=True,exist_ok=True)
with sqlite3.connect(f'{Path(args.source).resolve().as_uri()}?mode=ro',uri=True) as source:
    with sqlite3.connect(args.destination) as destination:
        source.backup(destination)
print(f'Backup created: {args.destination}')
