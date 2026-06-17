"""Common utility functions.

This module exposes common utility functions, for both individual tests and the
toplevel suite driver. In particular, they don't depend on the current
"thistest" instance.
"""

import os
from pathlib import Path
import sys


def exit_if(t, comment):
    """
    If `t` is true, print `comment` on the standard error stream and exit with
    error status code.
    """
    if t:
        sys.stderr.write(comment + "\n")
        exit(1)


def clear(f):
    """Remove file F if it exists"""
    if os.path.exists(f):
        os.remove(f)


def contents_of(filename: str) -> str:
    """
    Return the contents of filename as a single string. filename is expected to exist.
    """
    with open(filename) as fd:
        return fd.read()


def cat(filename: str, flush=False):
    """
    Print the contents of filename on stdout. filename is expected to exist
    """
    print(contents_of(filename), flush=flush)

def remove_file(filename: Path): 
    """
    Remove a file.
    """
    if filename.exists() and filename.is_file():
        filename.unlink()
