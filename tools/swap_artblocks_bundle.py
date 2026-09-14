#!/usr/bin/env python3
import ctypes
import os
import pathlib
import sys


def exchange(first, second):
    if sys.platform != 'darwin':
        raise OSError('Atomic Art Blocks publication requires macOS renamex_np(RENAME_SWAP)')
    first, second = pathlib.Path(first), pathlib.Path(second)
    if first.parent.resolve() != second.parent.resolve() or not first.is_dir() or not second.is_dir() or first.is_symlink() or second.is_symlink():
        raise ValueError('Atomic publication requires two sibling directories')
    libc = ctypes.CDLL(None, use_errno=True)
    rename = libc.renamex_np
    rename.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
    rename.restype = ctypes.c_int
    if rename(os.fsencode(first), os.fsencode(second), 0x00000002) != 0:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error))


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit('Usage: swap_artblocks_bundle.py existing-bundle verified-stage')
    exchange(sys.argv[1], sys.argv[2])
