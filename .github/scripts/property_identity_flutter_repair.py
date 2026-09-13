from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f"missing repair pattern: {label}")
    return text.replace(old, new, 1)


path = Path('mobile_app/lib/features/properties/domain/property_details.dart')
text = path.read_text()
summary_start = text.index('class PropertySummary {')
details_start = text.index('class PropertyDetails {')
input_start = text.index('class PropertyListingInput {')
summary = text[summary_start:details_start]
details = text[details_start:input_start]

summary = replace_once(
    summary,
    """    this.address,\n    this.buildingReference,\n    this.unitNumber,\n    this.floorNumber,\n    this.landBoundaryGeoJson,\n    this.duplicateCheckStatus,\n    this.duplicateCheckScore = 0,\n    this.status = 'published',\n""",
    """    this.address,\n    this.status = 'published',\n""",
    'PropertySummary constructor',
)

details = replace_once(
    details,
    """    this.address,\n    this.status = 'published',\n""",
    """    this.address,\n    this.buildingReference,\n    this.unitNumber,\n    this.floorNumber,\n    this.landBoundaryGeoJson,\n    this.duplicateCheckStatus,\n    this.duplicateCheckScore = 0,\n    this.status = 'published',\n""",
    'PropertyDetails constructor',
)

path.write_text(text[:summary_start] + summary + details + text[input_start:])

editor = Path('mobile_app/lib/features/properties/presentation/listing_editor_screen.dart')
text = editor.read_text()
replacements = {
    "                            if (_type != 'land') _landBoundaryGeoJson = null;": """                            if (_type != 'land') {\n                              _landBoundaryGeoJson = null;\n                            }""",
    "        if (_buildingReference.text.trim().isEmpty) return 'أدخل اسم أو رقم المبنى.';": """        if (_buildingReference.text.trim().isEmpty) {\n          return 'أدخل اسم أو رقم المبنى.';\n        }""",
    "        if (_unitNumber.text.trim().isEmpty) return 'أدخل رقم الوحدة.';": """        if (_unitNumber.text.trim().isEmpty) {\n          return 'أدخل رقم الوحدة.';\n        }""",
    "        if (_unitNeedsFloor && _floorNumber.text.trim().isEmpty) return 'أدخل رقم الدور.';": """        if (_unitNeedsFloor && _floorNumber.text.trim().isEmpty) {\n          return 'أدخل رقم الدور.';\n        }""",
    "    if (result.isDistinct) return true;": """    if (result.isDistinct) {\n      return true;\n    }""",
}
for old, new in replacements.items():
    text = text.replace(old, new)
editor.write_text(text)
print('Property Identity V2 generated Flutter repair applied')
