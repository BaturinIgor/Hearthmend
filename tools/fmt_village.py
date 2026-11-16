#!/usr/bin/env python3
"""Переписывает village.json в компактном виде: одна задача на строку."""
import json, os
p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Sources", "HearthCore", "Resources", "village.json")
v = json.load(open(p))
def one(t):
    return "{ " + ", ".join(f"{json.dumps(k)}: {json.dumps(val, ensure_ascii=False)}" for k, val in t.items()) + " }"
out = ['{', '  "districts": [']
for i, d in enumerate(v["districts"]):
    out += ['    {', f'      "id": {json.dumps(d["id"])},', '      "tasks": [']
    out += [f'        {one(t)}' + ("," if j < len(d["tasks"]) - 1 else "") for j, t in enumerate(d["tasks"])]
    out += ['      ]', '    }' + ("," if i < len(v["districts"]) - 1 else "")]
out += ['  ]', '}']
open(p, "w").write("\n".join(out) + "\n")
