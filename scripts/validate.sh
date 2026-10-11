#!/usr/bin/env bash
# Generate a current-source, fail-closed AIUI audit. Exit 2 is a valid blocked audit.
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
target_version="0.17.0"
python_bin="${PYTHON_BIN:-python3}"
export PYTHONDONTWRITEBYTECODE=1

if [[ -z "${SKILL_ROOT:-}" ]]; then
  for candidate in \
    "${CODEX_HOME:-$HOME/.codex}/skills/rokid-aiui-agent" \
    "$HOME/.agents/skills/rokid-aiui-agent"; do
    if [[ -f "$candidate/scripts/validate_aiui_audit.py" ]]; then
      SKILL_ROOT="$candidate"
      break
    fi
  done
fi

if [[ -z "${SKILL_ROOT:-}" ]]; then
  echo 'Set SKILL_ROOT to the installed rokid-aiui-agent skill directory.' >&2
  echo 'It must contain SKILL.md and scripts/validate_aiui_audit.py.' >&2
  exit 1
fi

skill_root="$(cd "$SKILL_ROOT" && pwd -P)"
for tool in fingerprint_aiui_project inventory_aiui_capabilities validate_aiui_project validate_aiui_audit; do
  if [[ ! -f "$skill_root/scripts/$tool.py" ]]; then
    echo "Missing skill tool: $skill_root/scripts/$tool.py" >&2
    exit 1
  fi
done

evidence_root="$project_root/.aiui-evidence"
mkdir -p "$evidence_root"
cd "$project_root"

"$python_bin" "$skill_root/scripts/fingerprint_aiui_project.py" "$project_root" \
  --repository-root "$project_root" \
  > "$evidence_root/fingerprint.txt" 2> "$evidence_root/fingerprint.stderr.log"

"$python_bin" "$skill_root/scripts/inventory_aiui_capabilities.py" "$project_root" \
  --target-version "$target_version" --repository-root "$project_root" \
  > "$evidence_root/inventory.json" 2> "$evidence_root/inventory.stderr.log"

set +e
"$python_bin" "$skill_root/scripts/validate_aiui_project.py" "$project_root" \
  --target-version "$target_version" --repository-root "$project_root" --strict --json \
  > "$evidence_root/project-validation.json" 2> "$evidence_root/project-validation.stderr.log"
structure_status=$?
set -e
if [[ "$structure_status" -ne 0 ]]; then
  echo "AIUI strict structure validation failed; inspect .aiui-evidence/project-validation.json." >&2
  exit "$structure_status"
fi

# Read the exact canonical contracts from the selected skill rather than maintain
# a second registry. These are source policies, not executed evidence or trust keys.
"$python_bin" - "$skill_root" "$evidence_root" "$target_version" <<'PY'
import hashlib
import importlib.util
import json
import sys
from pathlib import Path

skill_root, evidence_root, target_version = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
spec = importlib.util.spec_from_file_location(
    "aiui_audit_contracts", skill_root / "scripts/validate_aiui_audit.py"
)
contracts = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = contracts
spec.loader.exec_module(contracts)
report = json.loads((evidence_root / "inventory.json").read_text(encoding="utf-8"))
fingerprint = (evidence_root / "fingerprint.txt").read_text(encoding="utf-8").strip()
if report.get("schemaVersion") != 2 or report.get("targetVersion") != target_version:
    raise SystemExit("Expected the selected AIUI schema-2 inventory.")
if report["projectRevision"] != fingerprint:
    raise SystemExit("Source changed between fingerprint and inventory; rerun validation.")
if report["versionViolations"]:
    raise SystemExit("Resolve inventory versionViolations before generating the audit.")
if not report["inputGates"]:
    raise SystemExit("Peak Now must expose input gates before auditing; no unsigned N/A proof is accepted.")

layer_order = ("SOURCE", "STATIC", "LOGIC", "AIX", "STUDIO", "DEVICE")
default_gates = {
    "UX-TARGET": "all-targets",
    "UX-STATE": "all-states",
    "UX-TEXT": "boundary-text",
    "UX-FOCUS": "focus-model",
    "UX-RECOVERY": "failure-recovery",
    "UX-LIFECYCLE": "page-lifecycle",
    "UX-VISUAL": "visual-system",
    "UX-ENVIRONMENT": "optical-scenes",
    "UX-MOTION": "motion-performance",
}

def ordered_layers(layers):
    return tuple(layer for layer in layer_order if layer in layers)

def blocked_evidence(layers):
    reasons = {
        "SOURCE": "selected-version official support inspection not captured for this row",
        "STATIC": "local structural checks lack external RUNNER attestation",
        "LOGIC": "trusted current-revision LOGIC capture unavailable",
        "AIX": "trusted current-revision AIX capture unavailable",
        "STUDIO": "authenticated selected-runtime Studio capture unavailable",
        "DEVICE": "physical Rokid device and authenticated capture unavailable",
    }
    return "; ".join(f"{layer}=blocked:{reasons[layer]}" for layer in layers)

def table(header, rows):
    return "\n".join(
        "| " + " | ".join(str(cell).replace("\\", "\\\\").replace("|", "\\|") for cell in row) + " |"
        for row in (header, tuple("---" for _ in header), *rows)
    )

ux_rows, cap_rows, required_gates, blocked_ids = [], [], [], []
for family, required_layers in contracts.UX_REQUIRED_LAYERS.items():
    layers = ordered_layers(required_layers)
    gates = [entry["gate"] for entry in report["inputGates"]] if family == "UX-INPUT" else [default_gates[family]]
    surface, risk, criterion = contracts.UX_CONTRACTS[family]
    for index, gate in enumerate(gates, 1):
        identifier = f"{family}-GATE{index}" if len(gates) > 1 else family
        ux_rows.append([
            f"[{identifier}] {{gate={gate}}}", surface, risk,
            f"{{contract={contracts.UX_CONTRACT_TOKENS[family]}}} {criterion}",
            ", ".join(layers), "BLOCKED", blocked_evidence(layers),
        ])
        blocked_ids.append(identifier)
        required_gates.extend(f"{identifier}@{layer}" for layer in layers)

by_claim = {f"{item['family']}@{item['gate']}": item for item in report["items"]}
if len(by_claim) != len(report["items"]) or sorted(by_claim) != report["claimedCapabilities"]:
    raise SystemExit("Inventory item and capability ledgers are not exact.")
for claim in report["claimedCapabilities"]:
    item = by_claim[claim]
    family, gate = item["family"], item["gate"]
    policy = contracts.CAPABILITY_POLICIES[family]
    if family == "project.unregistered":
        identifier = "CAP-UNREGISTERED-" + gate.removeprefix("unregistered-").upper()
        label = "Unregistered project capability"
    else:
        instance = hashlib.sha256(gate.encode("utf-8")).hexdigest()[:12].upper()
        identifier = f"{policy.base_id}-{instance}"
        if item["policyState"] == "binding-unresolved":
            identifier += "-PROVISIONAL"
        label = family.replace(".", " ").replace("-", " ").capitalize()
    layers = ordered_layers(policy.layers)
    mechanism = item.get("mechanism", "")
    if mechanism.startswith("CLAIM:") and "@" in mechanism:
        surface = mechanism.split("@", 1)[1].split(":", 1)[0]
    elif mechanism.startswith("target:"):
        surface = mechanism.split(":", 1)[1]
    else:
        surface = ",".join(report["supportedSurfaces"]) or "UNAVAILABLE"
    source_cell = "; ".join(
        f"{role}=[{role.lower()}]({url})"
        for role, url in sorted(contracts.CAPABILITY_SOURCE_POLICIES[family])
    )
    behavior_cells = [
        contracts.capability_contract_cell(family, path, description)
        for path, description in zip(
            ("positive", "negative-fallback", "lifecycle-cleanup"),
            contracts.CAPABILITY_BEHAVIOR_CONTRACTS[family],
        )
    ]
    cap_rows.append([
        f"[{identifier}] {{family={family}}} {{gate={gate}}} {label}",
        f"AIUI {target_version}; device=UNAVAILABLE; surface={surface}",
        item["apiBinding"], item["declarationBinding"], source_cell,
        *behavior_cells, ", ".join(layers), "BLOCKED", blocked_evidence(layers),
    ])
    blocked_ids.append(identifier)
    required_gates.extend(f"{identifier}@{layer}" for layer in layers)

metadata = [
    f"Project revision: {report['projectRevision']}",
    f"Canonical version: AIUI {target_version}",
    "Import root: .",
    "Device/host: UNAVAILABLE",
    "Supported surfaces: " + (",".join(report["supportedSurfaces"]) or "UNAVAILABLE"),
    "Inputs: " + ",".join(sorted(f"{entry['kind']}@{entry['gate']}" for entry in report["inputGates"])),
    "Claimed capabilities: " + ",".join(report["claimedCapabilities"]),
]
audit = (
    "\n".join(metadata)
    + "\n\n## Project UX evidence matrix\n\n" + table(contracts.UX_HEADERS, ux_rows)
    + "\n\n## Per-capability matrix\n\n" + table(contracts.CAPABILITY_HEADERS, cap_rows)
    + "\n\n## Final release decision\n\n"
    + "Final status: BLOCKED\nRelease-ready: NO\n"
    + "Reason: FAIL=[none]; BLOCKED=[" + ",".join(sorted(blocked_ids)) + "]\n"
    + "Required gates: " + ",".join(sorted(required_gates)) + "\n"
)
(evidence_root / "AIUI-AUDIT.md").write_text(audit, encoding="utf-8")
print(f"Generated exact matrices: {len(ux_rows)} UX rows; {len(cap_rows)} capability rows.")
print(f"Quarantined inventory items: {len(report['unmatchedSymbols'])}; version violations: 0.")
PY

set +e
"$python_bin" "$skill_root/scripts/validate_aiui_audit.py" "$evidence_root/AIUI-AUDIT.md" \
  --repository-root "$project_root" --import-root . \
  > "$evidence_root/audit-validation.log" 2> "$evidence_root/audit-validation.stderr.log"
audit_status=$?
set -e
cat "$evidence_root/audit-validation.log"
if [[ "$audit_status" -eq 1 ]]; then
  cat "$evidence_root/audit-validation.stderr.log" >&2
elif [[ "$audit_status" -eq 2 ]]; then
  echo 'Local strict structure passed. Release gates remain BLOCKED; see .aiui-evidence/AIUI-AUDIT.md.'
fi
exit "$audit_status"
