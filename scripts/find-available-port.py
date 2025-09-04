#!/usr/bin/env python3
"""
find-available-port.py - Dynamic Port Allocation Script

This script finds the next available port starting from a preferred port number.
It checks if ports are available and returns the first free port found.

Usage:
    python3 find-available-port.py <preferred_port> [max_attempts]

Arguments:
    preferred_port  - Starting port number to check (e.g., 8000)
    max_attempts    - Maximum number of ports to try (default: 100)

Returns:
    Available port number on stdout, or exits with error code 1 if none found.

Examples:
    python3 find-available-port.py 8000
    python3 find-available-port.py 8000 50
"""

import sys
import socket
import logging
from typing import Optional

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    stream=sys.stderr  # Log to stderr so stdout only contains the port number
)
logger = logging.getLogger(__name__)


def is_port_available(port: int, host: str = 'localhost') -> bool:
    """
    Check if a port is available for binding.
    
    Args:
        port: Port number to check
        host: Host to bind to (default: localhost)
    
    Returns:
        True if port is available, False otherwise
    """
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            result = sock.bind((host, port))
            return True
    except (socket.error, OSError) as e:
        logger.debug(f"Port {port} is not available: {e}")
        return False


def find_available_port(preferred_port: int, max_attempts: int = 100, host: str = 'localhost') -> Optional[int]:
    """
    Find the next available port starting from preferred_port.
    
    Args:
        preferred_port: Starting port number
        max_attempts: Maximum number of consecutive ports to try
        host: Host to bind to
    
    Returns:
        Available port number, or None if no port found
    """
    logger.info(f"Searching for available port starting from {preferred_port}")
    
    for attempt in range(max_attempts):
        port = preferred_port + attempt
        
        # Skip ports outside valid range
        if port > 65535:
            logger.warning(f"Port {port} exceeds maximum port number (65535)")
            break
            
        # Skip well-known system ports if we're in that range
        if port < 1024:
            logger.debug(f"Skipping system port {port}")
            continue
            
        logger.debug(f"Checking port {port} (attempt {attempt + 1}/{max_attempts})")
        
        if is_port_available(port, host):
            logger.info(f"Found available port: {port}")
            return port
        else:
            logger.debug(f"Port {port} is in use")
    
    logger.error(f"No available port found after {max_attempts} attempts starting from {preferred_port}")
    return None


def validate_port(port_str: str) -> int:
    """
    Validate and convert port string to integer.
    
    Args:
        port_str: Port number as string
    
    Returns:
        Port number as integer
    
    Raises:
        ValueError: If port is invalid
    """
    try:
        port = int(port_str)
        if port < 1 or port > 65535:
            raise ValueError(f"Port must be between 1 and 65535, got {port}")
        return port
    except ValueError as e:
        raise ValueError(f"Invalid port number '{port_str}': {e}")


def show_usage():
    """Display usage information"""
    print(__doc__)


def main():
    """Main entry point"""
    # Handle command line arguments
    if len(sys.argv) < 2 or sys.argv[1] in ['-h', '--help', 'help']:
        show_usage()
        sys.exit(0)
    
    try:
        # Parse arguments
        preferred_port = validate_port(sys.argv[1])
        max_attempts = 100  # Default
        
        if len(sys.argv) > 2:
            try:
                max_attempts = int(sys.argv[2])
                if max_attempts < 1:
                    raise ValueError("max_attempts must be positive")
            except ValueError as e:
                logger.error(f"Invalid max_attempts: {e}")
                sys.exit(1)
        
        # Find available port
        available_port = find_available_port(preferred_port, max_attempts)
        
        if available_port is not None:
            # Output only the port number to stdout for easy parsing
            print(available_port)
            sys.exit(0)
        else:
            logger.error("No available port found")
            sys.exit(1)
            
    except ValueError as e:
        logger.error(f"Invalid arguments: {e}")
        sys.exit(1)
    except KeyboardInterrupt:
        logger.info("Port search cancelled by user")
        sys.exit(1)
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
