"""
dbc_to_lua.py — парсит Spell.dbc (WotLK 3.3.5a) и генерирует spell_data_<classId>.lua
Использование:
    python dbc_to_lua.py --dbc ./data/dbc/Spell.dbc --out ./lua_scripts/
"""

import struct
import argparse
import os
import sys
import re
from collections import defaultdict

# ======== СМЕЩЕНИЯ КОЛОНОК (0-based, каждая = 4 байта) ========
COL_ID            = 0
COL_ATTRIBUTES    = 5
COL_SPELL_LEVEL   = 39
COL_SPELL_FAMILY  = 208
COL_NAME          = 136
COL_RANK_STR      = 153
FAMILY_NAMES = {3, 4, 5, 6, 7, 8, 9, 10, 11, 15}

# ПАССИВНЫЕ НАВЫКИ — полное исключение
PASSIVE_FLAGS = (
    0x40 |  # SPELL_ATTR0_PASSIVE
    0x100 | # SPELL_ATTR0_HIDDEN_CLIENTSIDE
    0x4000  # SPELL_ATTR0_NOT_SHAPESHIFT
)

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

def parse_rank(rank_str):
    m = re.search(r'(\d+)', rank_str)
    return int(m.group(1)) if m else 0

def parse_dbc(dbc_path):
    with open(dbc_path, 'rb') as f:
        data = f.read()

    magic = data[:4]
    if magic != b'WDBC':
        print(f"[ERROR] Не DBC файл: {dbc_path}", file=sys.stderr)
        sys.exit(1)

    record_count = read_uint32(data, 4)
    field_count  = read_uint32(data, 8)
    record_size  = read_uint32(data, 12)
    string_size  = read_uint32(data, 16)

    header_size   = 20
    strings_start = header_size + record_count * record_size
    string_block  = data[strings_start : strings_start + string_size]

    print(f"[INFO] Записей: {record_count}, полей: {field_count}, размер записи: {record_size}")

    spells = []

    for i in range(record_count):
        def col(c):
            return read_uint32(data, header_size + i * record_size + c * 4)

        spell_id    = col(COL_ID)
        attributes  = col(COL_ATTRIBUTES)
        spell_level = col(COL_SPELL_LEVEL)
        family_name = col(COL_SPELL_FAMILY)
        name_off    = col(COL_NAME)
        rank_off    = col(COL_RANK_STR)

        # ❌ СТРОГОЕ ИСКЛЮЧЕНИЕ ПАССИВНЫХ НАВЫКОВ
        if attributes & PASSIVE_FLAGS != 0:
            continue
        if spell_level == 0 or spell_level > 80:
            continue

        name     = read_cstring(string_block, name_off)
        rank_str = read_cstring(string_block, rank_off)
        rank     = parse_rank(rank_str)

        if rank == 0 or family_name not in FAMILY_NAMES or not name:
            continue

        spells.append({
            'id':       spell_id,
            'name':     name,
            'rank':     rank,
            'reqLevel': spell_level,
            'family':   family_name,
        })

    return spells

def write_lua(spells, out_path, family_id):
    def esc(s):
        return s.replace('\\', '\\\\').replace('"', '\\"')

    lines = [
        f'-- SpellFamilyName = {family_id}',
        'local M = {}',
        '',
        '-- { id, name, rank, reqLevel, family }',
        'M.spells = {',
    ]

    for s in spells:
        lines.append(
            '  {{ id={}, name="{}", rank={}, reqLevel={}, family={} }},'.format(
                s['id'], esc(s['name']), s['rank'], s['reqLevel'], s['family']
            )
        )

    lines += ['}', '', 'return M']

    with open(out_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))

    print(f"[INFO] Записано {len(spells)} спеллов -> {out_path}")

def main():
    parser = argparse.ArgumentParser(description='Spell.dbc -> spell_data_<classId>.lua')
    parser.add_argument('--dbc', default='./data/dbc/Spell.dbc')
    parser.add_argument('--out', default='./lua_scripts/', help='Папка для выходных файлов')
    args = parser.parse_args()

    if not os.path.exists(args.dbc):
        print(f"[ERROR] Файл не найден: {args.dbc}", file=sys.stderr)
        sys.exit(1)

    os.makedirs(args.out, exist_ok=True)

    print(f"[INFO] Парсинг {args.dbc} ...")
    spells = parse_dbc(args.dbc)
    print(f"[INFO] Отфильтровано {len(spells)} спеллов")

    # Группируем по family
    by_family = defaultdict(list)
    for s in spells:
        by_family[s['family']].append(s)

    # Пишем отдельный файл для каждого класса
    for family_id, family_spells in sorted(by_family.items()):
        out_path = os.path.join(args.out, f"spell_data_{family_id}.lua")
        write_lua(family_spells, out_path, family_id)

    print(f"[INFO] Готово. Создано {len(by_family)} файлов в {args.out}")
    print("[INFO] Найденные family ID:")
    for family_id, family_spells in sorted(by_family.items()):
        print(f"  family={family_id:3d}  спеллов={len(family_spells)}")

if __name__ == '__main__':
    main()
