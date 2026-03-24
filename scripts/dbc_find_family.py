"""
Находит колонку SpellFamilyName — ищет колонку где у спеллов одного класса
одинаковое ненулевое значение, а у спеллов разных классов — разное.

Известные пары одного класса:
  Маг:     116 (Frostbolt), 2136 (Fire Blast), 122 (Frost Nova), 1953 (Blink)
  Воин:    78 (Heroic Strike), 100 (Charge), 1464 (Slam), 6572 (Revenge)
  Жрец:    17 (Power Word: Shield), 139 (Renew)
"""

import struct
import argparse
import sys

def read_uint32(data, offset):
    return struct.unpack_from('<I', data, offset)[0]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--dbc', default='./data/dbc/Spell.dbc')
    args = parser.parse_args()

    with open(args.dbc, 'rb') as f:
        data = f.read()

    record_count = read_uint32(data, 4)
    record_size  = read_uint32(data, 12)
    header_size  = 20
    cols         = record_size // 4

    # Строим индекс id -> offset
    id_to_off = {}
    for i in range(record_count):
        off = header_size + i * record_size
        sid = read_uint32(data, off)
        id_to_off[sid] = off

    mage_ids    = [116, 2136, 122, 1953, 118, 120]
    warrior_ids = [78, 100, 1464, 6572]
    priest_ids  = [17, 139]

    def get_col(spell_id, col):
        off = id_to_off.get(spell_id)
        if off is None:
            return None
        return read_uint32(data, off + col * 4)

    print("Ищем колонку где все спеллы Мага имеют одинаковое значение,")
    print("все спеллы Воина — другое одинаковое, и они отличаются друг от друга.\n")

    for c in range(cols):
        mage_vals    = [get_col(i, c) for i in mage_ids    if get_col(i, c) is not None]
        warrior_vals = [get_col(i, c) for i in warrior_ids if get_col(i, c) is not None]
        priest_vals  = [get_col(i, c) for i in priest_ids  if get_col(i, c) is not None]

        mage_same    = len(set(mage_vals))    == 1 and mage_vals[0]    != 0
        warrior_same = len(set(warrior_vals)) == 1 and warrior_vals[0] != 0
        priest_same  = len(set(priest_vals))  == 1 and priest_vals[0]  != 0

        all_same  = mage_same and warrior_same and priest_same
        all_diff  = len({mage_vals[0], warrior_vals[0], priest_vals[0]}) == 3

        if all_same and all_diff:
            print(f"*** НАЙДЕНО: col {c} ***")
            print(f"  Маг    ({mage_ids}):    {mage_vals[0]}")
            print(f"  Воин   ({warrior_ids}): {warrior_vals[0]}")
            print(f"  Жрец   ({priest_ids}):  {priest_vals[0]}")
            print()

        # Также печатаем кандидатов где хотя бы маг и воин одинаковы
        elif mage_same and warrior_same and mage_vals[0] != warrior_vals[0]:
            print(f"  Кандидат col {c}: Маг={mage_vals[0]}, Воин={warrior_vals[0]}, Жрец={priest_vals}")

if __name__ == '__main__':
    main()