#!/usr/bin/env python3
"""Verifica la trazabilidad entre requerimientos y pruebas.

1. Lee los requerimientos declarados en docs/01-requerimientos.md (RF, RNF, RT, RS).
2. Recorre todas las pruebas automatizadas:
   - tests/*.tftest.hcl          (bloques `run`)
   - tests/static/*.py           (funciones test_*)
   - tests/integration/*.py      (funciones test_*)
   - scripts/smoke_test.sh       (verificaciones `check`)
   y obtiene los requerimientos que cubre cada una (por su nombre, p. ej. `rs04_`, y
   por los IDs citados en su cuerpo o mensajes de error).
3. Genera reports/trazabilidad.md (requerimiento → pruebas) y reports/trazabilidad.xml (JUnit).
4. Termina con error si algún requerimiento no tiene pruebas o si una prueba cita un
   requerimiento inexistente. Así el pipeline impide perder la correspondencia.
"""
from __future__ import annotations

import re
import sys
from collections import defaultdict
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parents[1]
REPORTS = ROOT / "reports"
ID_RE = re.compile(r"\b(RF|RNF|RT|RS)-(\d{2})\b")
NAME_RE = re.compile(r"(?<![a-z])(rf|rnf|rt|rs)(\d{2})(?=_|\b)")

LEVELS = {
    "tftest": "Unitaria (terraform test)",
    "static": "Estática (pytest)",
    "integration": "Integración (pytest + AWS)",
    "smoke": "Humo (post-despliegue)",
}


def ids_in(text: str) -> set[str]:
    return {f"{a}-{b}" for a, b in ID_RE.findall(text)} | {f"{a.upper()}-{b}" for a, b in NAME_RE.findall(text)}


def balanced_block(text: str, start: int) -> str:
    depth = 0
    for j in range(start, len(text)):
        depth += {"{": 1, "}": -1}.get(text[j], 0)
        if depth == 0:
            return text[start : j + 1]
    return text[start:]


def requirements() -> dict[str, str]:
    doc = (ROOT / "docs" / "01-requerimientos.md").read_text(encoding="utf-8")
    reqs = {}
    for line in doc.splitlines():
        m = re.match(r"^\|\s*((?:RF|RNF|RT|RS)-\d{2})\s*\|\s*([^|]+)\|", line)
        if m:
            reqs.setdefault(m.group(1), m.group(2).strip())
    return reqs


def collect_tests() -> list[tuple[str, str, str, set[str]]]:
    """(nivel, archivo, nombre, ids)."""
    tests = []
    for path in sorted((ROOT / "tests").glob("*.tftest.hcl")):
        text = path.read_text(encoding="utf-8")
        for m in re.finditer(r'^run "([^"]+)" \{', text, re.M):
            body = balanced_block(text, m.end() - 1)
            tests.append(("tftest", path.name, m.group(1), ids_in(m.group(1)) | ids_in(body)))

    for level in ("static", "integration"):
        for path in sorted((ROOT / "tests" / level).glob("test_*.py")):
            text = path.read_text(encoding="utf-8")
            funcs = list(re.finditer(r"^\s*def (test_\w+)\(", text, re.M))
            for i, m in enumerate(funcs):
                end = funcs[i + 1].start() if i + 1 < len(funcs) else len(text)
                # El cuerpo termina antes de comentarios de sección, clases o decoradores
                # siguientes, para no atribuir a esta prueba los IDs de la sección que sigue.
                stop = re.compile(r"^\s*(# -{5,}|class |@)", re.M).search(text, m.end(), end)
                body = text[m.start() : stop.start() if stop else end]
                tests.append((level, path.name, m.group(1), ids_in(m.group(1)) | ids_in(body)))

    smoke = (ROOT / "scripts" / "smoke_test.sh").read_text(encoding="utf-8")
    for m in re.finditer(r'^check "([^"]+)"', smoke, re.M):
        tests.append(("smoke", "smoke_test.sh", m.group(1), ids_in(m.group(1))))
    return tests


def main() -> int:
    reqs = requirements()
    tests = collect_tests()
    by_req: dict[str, list[tuple[str, str, str]]] = defaultdict(list)
    unknown: list[str] = []
    untagged: list[str] = []

    for level, file, name, ids in tests:
        if not ids:
            untagged.append(f"{file}::{name}")
        for rid in ids:
            if rid in reqs:
                by_req[rid].append((level, file, name))
            else:
                unknown.append(f"{file}::{name} cita {rid}")

    missing = [r for r in reqs if not by_req.get(r)]

    REPORTS.mkdir(exist_ok=True)
    lines = [
        "# Trazabilidad requerimiento → prueba (salida de check_traceability.py)",
        "",
        f"Requerimientos: **{len(reqs)}** · Pruebas analizadas: **{len(tests)}** · "
        f"Requerimientos cubiertos: **{len(reqs) - len(missing)}/{len(reqs)}**",
        "",
        "| Requerimiento | Descripción | N.º pruebas | Niveles | Pruebas |",
        "|---|---|---|---|---|",
    ]
    for rid, desc in reqs.items():
        items = by_req.get(rid, [])
        levels = sorted({LEVELS[lv] for lv, _, _ in items})
        names = "<br>".join(f"`{f}::{n}`" for _, f, n in items[:8]) + (f"<br>… y {len(items) - 8} más" if len(items) > 8 else "")
        lines.append(f"| {rid} | {desc} | {len(items)} | {', '.join(levels) or '—'} | {names or '**SIN PRUEBAS**'} |")
    lines += ["", "## Pruebas por nivel", "", "| Nivel | Cantidad |", "|---|---|"]
    for lv, label in LEVELS.items():
        lines.append(f"| {label} | {sum(1 for t in tests if t[0] == lv)} |")
    (REPORTS / "trazabilidad.md").write_text("\n".join(lines) + "\n", encoding="utf-8")

    cases = []
    for rid, desc in reqs.items():
        n = len(by_req.get(rid, []))
        failure = "" if n else f'<failure message="{rid} sin pruebas asociadas"/>'
        cases.append(f'  <testcase classname="trazabilidad" name="{rid} {escape(desc)} ({n} pruebas)">{failure}</testcase>')
    xml = (
        f'<?xml version="1.0" encoding="UTF-8"?>\n<testsuite name="trazabilidad-requerimientos" '
        f'tests="{len(reqs)}" failures="{len(missing)}">\n' + "\n".join(cases) + "\n</testsuite>\n"
    )
    (REPORTS / "trazabilidad.xml").write_text(xml, encoding="utf-8")

    print(f"Requerimientos: {len(reqs)} | Pruebas: {len(tests)} | Cubiertos: {len(reqs) - len(missing)}/{len(reqs)}")
    for lv, label in LEVELS.items():
        print(f"  {label}: {sum(1 for t in tests if t[0] == lv)}")
    if untagged:
        print("Pruebas sin requerimiento asociado:\n  " + "\n  ".join(untagged))
    if unknown:
        print("Referencias a requerimientos inexistentes:\n  " + "\n  ".join(unknown))
    if missing:
        print("Requerimientos SIN pruebas: " + ", ".join(missing))
    ok = not (missing or unknown or untagged)
    print("TRAZABILIDAD OK" if ok else "TRAZABILIDAD INCOMPLETA")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
