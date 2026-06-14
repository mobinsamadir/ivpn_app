with open("pubspec.yaml", "r") as f:
    lines = f.readlines()

new_lines = []
skip = False
for line in lines:
    if line.startswith("<<<<<<< HEAD"):
        skip = True
        new_lines.append("  screen_retriever: ^0.2.1\n")
    elif line.startswith("======="):
        pass
    elif line.startswith(">>>>>>> origin/main"):
        skip = False
    else:
        if not skip:
            new_lines.append(line)

with open("pubspec.yaml", "w") as f:
    f.writelines(new_lines)
