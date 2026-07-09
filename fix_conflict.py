import sys

def main():
    try:
        with open('lib/widgets/config_card.dart', 'r') as f:
            lines = f.readlines()
    except Exception as e:
        print(f"Error reading file: {e}")
        return

    out_lines = []
    in_conflict = False
    in_my_code = False
    in_their_code = False

    for i in range(len(lines)):
        line = lines[i]

        if line.startswith('<<<<<<<'):
            in_conflict = True
            in_my_code = True
            continue

        if line.startswith('======='):
            in_my_code = False
            in_their_code = True
            continue

        if line.startswith('>>>>>>>'):
            in_conflict = False
            in_their_code = False
            continue

        if in_conflict:
            if in_their_code:
                # We want their code (_ConfigInfo)
                out_lines.append(line)
        else:
            out_lines.append(line)

    with open('lib/widgets/config_card.dart', 'w') as f:
        f.writelines(out_lines)
    print("Conflict resolved programmatically.")

if __name__ == '__main__':
    main()
