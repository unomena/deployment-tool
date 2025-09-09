#!/usr/bin/env python3
"""
PostgreSQL Database and User Permissions Listing Script

This script connects to PostgreSQL using root credentials from config.yml
and lists all databases with their users and permissions.

Usage:
    python3 list-database-permissions.py [database_name]

Arguments:
    database_name (optional): Filter results to show only this database
"""

import sys
import os
import yaml
import psycopg2
from psycopg2 import sql
import argparse
from typing import Dict, List, Optional, Tuple

# Add the project root to Python path for imports
script_dir = os.path.dirname(os.path.abspath(__file__))
project_root = os.path.dirname(script_dir)
sys.path.insert(0, project_root)

def load_config() -> Dict:
    """Load configuration from config.yml file."""
    config_path = os.path.join(project_root, 'config.yml')
    
    if not os.path.exists(config_path):
        print(f"Error: Configuration file not found at {config_path}")
        sys.exit(1)
    
    try:
        with open(config_path, 'r') as f:
            config = yaml.safe_load(f)
        return config
    except Exception as e:
        print(f"Error loading configuration: {e}")
        sys.exit(1)

def get_postgresql_config() -> Optional[Dict]:
    """Get PostgreSQL configuration from config file."""
    config = load_config()
    
    if 'databases' not in config:
        print("Error: No databases configuration found in config.yml")
        return None
    
    # Find the first PostgreSQL database configuration
    for db_config in config['databases']:
        if db_config.get('type') == 'postgresql':
            return db_config
    
    print("Error: No PostgreSQL database configuration found in config.yml")
    return None

def connect_to_postgres(db_config: Dict) -> psycopg2.extensions.connection:
    """Connect to PostgreSQL using root credentials."""
    try:
        conn = psycopg2.connect(
            host=db_config['host'],
            port=db_config['port'],
            user=db_config['root_user'],
            password=db_config['root_password'],
            database='postgres'  # Connect to default postgres database
        )
        return conn
    except Exception as e:
        print(f"Error connecting to PostgreSQL: {e}")
        sys.exit(1)

def get_databases(conn: psycopg2.extensions.connection, filter_db: Optional[str] = None) -> List[str]:
    """Get list of databases, optionally filtered by name."""
    try:
        with conn.cursor() as cur:
            if filter_db:
                cur.execute(
                    "SELECT datname FROM pg_database WHERE datistemplate = false AND datname = %s ORDER BY datname",
                    (filter_db,)
                )
            else:
                cur.execute(
                    "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname"
                )
            
            databases = [row[0] for row in cur.fetchall()]
            return databases
    except Exception as e:
        print(f"Error getting databases: {e}")
        return []

def get_database_users_and_permissions(conn: psycopg2.extensions.connection, database: str) -> List[Tuple[str, List[str]]]:
    """Get users and their permissions for a specific database."""
    users_permissions = []
    
    try:
        with conn.cursor() as cur:
            # First, get the database owner
            cur.execute("""
                SELECT r.rolname as owner
                FROM pg_database d
                JOIN pg_roles r ON d.datdba = r.oid
                WHERE d.datname = %s
            """, (database,))
            
            owner_result = cur.fetchone()
            db_owner = owner_result[0] if owner_result else None
            
            # Get all non-system roles
            cur.execute("""
                SELECT rolname, rolsuper, rolcreatedb, rolcanlogin
                FROM pg_roles 
                WHERE rolname NOT LIKE 'pg_%'
                ORDER BY rolname
            """)
            
            for row in cur.fetchall():
                username = row[0]
                is_superuser = row[1]
                can_create_db = row[2] 
                can_login = row[3]
                
                permissions = []
                
                # Add role attributes
                if is_superuser:
                    permissions.append("SUPERUSER")
                if can_create_db:
                    permissions.append("CREATEDB")
                if can_login:
                    permissions.append("LOGIN")
                else:
                    permissions.append("NOLOGIN")
                
                # Check database-specific privileges
                try:
                    cur.execute("SELECT has_database_privilege(%s, %s, 'CONNECT')", (username, database))
                    if cur.fetchone()[0]:
                        permissions.append("CONNECT")
                except:
                    pass
                
                try:
                    cur.execute("SELECT has_database_privilege(%s, %s, 'CREATE')", (username, database))
                    if cur.fetchone()[0]:
                        permissions.append("CREATE")
                except:
                    pass
                
                try:
                    cur.execute("SELECT has_database_privilege(%s, %s, 'TEMPORARY')", (username, database))
                    if cur.fetchone()[0]:
                        permissions.append("TEMPORARY")
                except:
                    pass
                
                # Check if user is the database owner
                if db_owner and username == db_owner:
                    permissions.append("OWNER")
                
                # Only include users who have some permissions or can login
                if permissions and (can_login or is_superuser or username == db_owner):
                    users_permissions.append((username, permissions))
            
            return users_permissions
            
    except Exception as e:
        print(f"Error getting users and permissions for database '{database}': {e}")
        import traceback
        traceback.print_exc()
        return []

def print_database_permissions(databases_info: Dict[str, List[Tuple[str, List[str]]]]):
    """Print formatted database and user permissions information."""
    if not databases_info:
        print("No databases found or accessible.")
        return
    
    print("=" * 80)
    print("PostgreSQL Databases and User Permissions")
    print("=" * 80)
    
    for database, users_permissions in databases_info.items():
        print(f"\n📁 Database: {database}")
        print("-" * 50)
        
        if not users_permissions:
            print("  No users with explicit permissions found.")
        else:
            for username, permissions in users_permissions:
                print(f"  👤 User: {username}")
                if permissions:
                    for perm in sorted(set(permissions)):
                        print(f"     • {perm}")
                else:
                    print("     • No specific permissions")
                print()

def main():
    """Main function."""
    parser = argparse.ArgumentParser(
        description="List PostgreSQL databases and their users with permissions"
    )
    parser.add_argument(
        'database_name', 
        nargs='?', 
        help='Optional: Filter results to show only this database'
    )
    
    args = parser.parse_args()
    
    # Get PostgreSQL configuration
    db_config = get_postgresql_config()
    if not db_config:
        sys.exit(1)
    
    print(f"Connecting to PostgreSQL server: {db_config['host']}:{db_config['port']}")
    print(f"Using credentials for user: {db_config['root_user']}")
    
    # Connect to PostgreSQL
    conn = connect_to_postgres(db_config)
    
    try:
        # Get databases
        databases = get_databases(conn, args.database_name)
        
        if not databases:
            if args.database_name:
                print(f"Database '{args.database_name}' not found.")
            else:
                print("No databases found.")
            sys.exit(1)
        
        # Get users and permissions for each database
        databases_info = {}
        for database in databases:
            users_permissions = get_database_users_and_permissions(conn, database)
            databases_info[database] = users_permissions
        
        # Print results
        print_database_permissions(databases_info)
        
    finally:
        conn.close()

if __name__ == "__main__":
    main()
