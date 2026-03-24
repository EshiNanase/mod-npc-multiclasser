#!/usr/bin/env python3
"""
dbc_inspect2.py — ищет конкретные spell ID в Spell.dbc и показывает их поля.
Использование:
    python dbc_inspect2.py --dbc ./data/dbc/Spell.dbc --ids 133,116,78,100
"""

import struct
import argparse
import os
import sys

def read_uint32(data, offset):
    return struct.unpack_from('<I', data, offset)[0]

def read_cstring(string_block, offset):
    if offset == 0 or offset >= len(string_block):
        return ""
    try:
        end = string_block.index(b'\x00', offset)
        return string_block[offset:end].decode('utf-8', errors='replace')
    except ValueError:
        return ""

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--dbc', default='./data/dbc/Spell.dbc')
    parser.add_argument('--ids', default='133,116,78,100,1464,6572,2136,122,1953',
                        help='Spell ID через запятую')
    args = parser.parse_args()

    target_ids = set(int(x.strip()) for x in args.ids.split(','))

    with open(args.dbc, 'rb') as f:
        data = f.read()

    record_count = read_uint32(data, 4)
    field_count  = read_uint32(data, 8)
    record_size  = read_uint32(data, 12)
    string_size  = read_uint32(data, 16)

    header_size   = 20
    strings_start = header_size + record_count * record_size
    string_block  = data[strings_start : strings_start + string_size]

    print(f"Records: {record_count}, Fields: {field_count}, RecSize: {record_size}")
    print()

    found = set()
    for i in range(record_count):
        rec_off = header_size + i * record_size
        spell_id = read_uint32(data, rec_off)
        if spell_id not in target_ids:
            continue
        found.add(spell_id)

        print(f"=== Spell ID {spell_id} ===")
        cols = record_size // 4

        # Показываем только поля с ненулевыми значениями + соседей
        nonzero = []
        for c in range(cols):
            val = read_uint32(data, rec_off + c * 4)
            if val != 0:
                nonzero.append(c)

        # Показываем каждое ненулевое поле с контекстом ±1
        shown = set()
        to_show = set()
        for c in nonzero:
            to_show.update([c-1, c, c+1])

        for c in sorted(to_show):
            if c < 0 or c >= cols:
                continue
            val = read_uint32(data, rec_off + c * 4)
            s = ""
            if 0 < val < string_size:
                candidate = read_cstring(string_block, val)
                if candidate and len(candidate) > 1:
                    s = f'  -> "{candidate[:80]}"'
            marker = " <--" if c in nonzero else ""
            print(f"  {c:>4}: {val:>12}{s}{marker}")
        print()

    missing = target_ids - found
    if missing:
        print(f"Не найдены ID: {missing}")


if __name__ == '__main__':
    main()