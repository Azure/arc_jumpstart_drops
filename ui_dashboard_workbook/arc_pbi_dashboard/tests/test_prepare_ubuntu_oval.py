import bz2
from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET


SCRIPT = Path(__file__).resolve().parents[1] / "prepare_ubuntu_oval.py"
SPEC = importlib.util.spec_from_file_location("prepare_ubuntu_oval", SCRIPT)
oval = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(oval)
NOW = datetime(2026, 11, 3, 21, tzinfo=timezone.utc)


def fixture():
    return f"""<oval_definitions xmlns="{oval.OVAL_NS}"
        xmlns:common="{oval.COMMON_NS}" xmlns:linux="{oval.LINUX_NS}">
      <generator><common:timestamp>2026-11-03T12:12:46</common:timestamp></generator>
      <definitions><definition id="definition" class="patch">
        <metadata><title>USN-8794-1</title>
          <reference source="USN" ref_id="USN-8794-1"/>
          <reference source="CVE" ref_id="CVE-2026-58015"/>
          <advisory><issued date="2026-09-21T16:25:01Z"/>
            <cve priority="medium" cvss_score="5.9"
              cvss_vector="CVSS:3.1/AV:N/AC:H/PR:N/UI:N/S:U/C:H/I:N/A:N">CVE-2026-58015</cve>
          </advisory>
        </metadata>
        <criteria operator="AND"><criterion test_ref="test"/></criteria>
      </definition></definitions>
      <tests><linux:dpkginfo_test id="test" check="at least one">
        <linux:object object_ref="object"/><linux:state state_ref="state"/>
      </linux:dpkginfo_test></tests>
      <objects><linux:dpkginfo_object id="object">
        <linux:name var_ref="variable"/>
      </linux:dpkginfo_object></objects>
      <states><linux:dpkginfo_state id="state">
        <linux:evr datatype="debian_evr_string" operation="less than">2.72.4-0ubuntu2.10</linux:evr>
      </linux:dpkginfo_state></states>
      <variables><constant_variable id="variable" datatype="string">
        <value>libglib2.0-0</value><value>libglib2.0-bin</value>
      </constant_variable></variables>
    </oval_definitions>"""


def parse(text=None):
    return oval.parse_feed((text or fixture()).encode(), "jammy", NOW)


class PrepareUbuntuOvalTests(unittest.TestCase):
    def test_extracts_binary_targets_and_versioned_cve_metadata(self):
        data = parse()
        notice = data["notices"][0]
        self.assertEqual(notice["id"], "USN-8794-1")
        self.assertEqual(notice["cves_ids"], ["CVE-2026-58015"])
        self.assertEqual(notice["release_packages"]["jammy"], [
            {"name": name, "version": "2.72.4-0ubuntu2.10", "is_source": False}
            for name in ("libglib2.0-0", "libglib2.0-bin")
        ])
        self.assertEqual(data["cves"]["CVE-2026-58015"], {
            "id": "CVE-2026-58015", "priority": "medium", "cvss_score": 5.9, "cvss_version": "3",
        })
        self.assertEqual(data["generator_timestamp"], "2026-11-03T12:12:46")

    def test_cvss4_is_not_mislabelled_as_cvss3(self):
        data = parse(fixture().replace("CVSS:3.1/", "CVSS:4.0/"))
        self.assertEqual(data["cves"]["CVE-2026-58015"]["cvss_version"], "4")
        self.assertEqual(data["cves"]["CVE-2026-58015"]["cvss_score"], 5.9)

    def test_genuine_absence_of_score_stays_null(self):
        data = parse(fixture().replace('cvss_score="5.9"', ""))
        self.assertIsNone(data["cves"]["CVE-2026-58015"]["cvss_score"])
        self.assertIsNone(data["cves"]["CVE-2026-58015"]["cvss_version"])

    def test_invalid_scores_and_unversioned_scores_fail(self):
        for score in ("NaN", "inf", "-1", "10.1", "invalid"):
            with self.subTest(score=score), self.assertRaises(ValueError):
                parse(fixture().replace('cvss_score="5.9"', f'cvss_score="{score}"'))
        with self.assertRaisesRegex(ValueError, "versioned vector"):
            parse(fixture().replace("CVSS:3.1/", ""))

    def test_wrong_namespace_missing_sections_and_dtd_fail(self):
        for text in (
            fixture().replace(oval.OVAL_NS, "wrong"),
            fixture().replace("<objects>", "<missing>").replace("</objects>", "</missing>"),
            '<!DOCTYPE oval_definitions [<!ENTITY x "unsafe">]>' + fixture(),
        ):
            with self.subTest(text=text[:70]), self.assertRaises(ValueError):
                parse(text)

    def test_missing_references_and_duplicate_identifiers_fail(self):
        with self.assertRaises(KeyError):
            parse(fixture().replace('object_ref="object"', 'object_ref="missing"'))
        root = ET.fromstring(fixture())
        objects = root.find(f"{{{oval.OVAL_NS}}}objects")
        objects.append(ET.fromstring(ET.tostring(objects[0])))
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            parse(ET.tostring(root, encoding="unicode"))

    def test_invalid_and_timezone_ambiguous_publication_dates_fail(self):
        for date in ("not-a-date", "2026-09-21T16:25:01"):
            with self.subTest(date=date), self.assertRaises(ValueError):
                parse(fixture().replace("2026-09-21T16:25:01Z", date))

    def test_old_notices_are_outside_the_24_month_window(self):
        with self.assertRaisesRegex(ValueError, "No recent"):
            parse(fixture().replace("2026-09-21T16:25:01Z", "2024-11-02T00:00:00Z"))
        self.assertEqual(oval.cutoff_date(datetime(2024, 2, 29, tzinfo=timezone.utc)).isoformat(), "2022-02-28")

    def test_negated_and_complex_tests_are_reported_not_evaluated(self):
        for text in (
            fixture().replace('<criteria operator="AND">', '<criteria operator="AND" negate="true">'),
            fixture().replace("dpkginfo_test", "variable_test"),
        ):
            data = parse(text)
            self.assertEqual(data["notices"][0]["release_packages"]["jammy"], [])
            self.assertEqual(sum(data["unsupported_test_counts"].values()), 1)

    def test_livepatch_is_explicitly_outside_package_update_coverage(self):
        root = ET.fromstring(fixture())
        definitions = root.find(f"{{{oval.OVAL_NS}}}definitions")
        extra = ET.fromstring(ET.tostring(definitions[0]))
        extra.set("id", "livepatch")
        ref = extra.find(f"{{{oval.OVAL_NS}}}metadata/{{{oval.OVAL_NS}}}reference")
        ref.set("source", "LSN")
        ref.set("ref_id", "LSN-0107-1")
        definitions.append(extra)
        data = parse(ET.tostring(root, encoding="unicode"))
        self.assertEqual(len(data["notices"]), 1)
        self.assertEqual(data["unsupported_definition_counts"], {"livepatch": 1})

    def test_conflicting_cve_ratings_are_rejected(self):
        root = ET.fromstring(fixture())
        definitions = root.find(f"{{{oval.OVAL_NS}}}definitions")
        extra = ET.fromstring(ET.tostring(definitions[0]))
        extra.set("id", "other")
        extra.find(f".//{{{oval.OVAL_NS}}}cve").set("cvss_score", "7")
        definitions.append(extra)
        with self.assertRaisesRegex(ValueError, "Inconsistent CVE"):
            parse(ET.tostring(root, encoding="unicode"))

    def test_decompression_rejects_truncation_trailing_data_and_size_overflow(self):
        class Response:
            status = 200

            def __init__(self, data):
                self.data = data

            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

            def read(self, size):
                return self.data[:size]

        payload = bz2.compress(fixture().encode())
        with patch.object(oval.urllib.request, "urlopen", return_value=Response(payload)):
            self.assertEqual(oval.download_feed("https://example.test/feed")[0], fixture().encode())
        for bad in (payload[:-1], payload + b"trailing"):
            with patch.object(oval.urllib.request, "urlopen", return_value=Response(bad)):
                with self.assertRaises(ValueError):
                    oval.download_feed("https://example.test/feed")
        with patch.object(oval.urllib.request, "urlopen", return_value=Response(payload)):
            with patch.object(oval, "MAX_XML_BYTES", 10), self.assertRaises(ValueError):
                oval.download_feed("https://example.test/feed")

    def test_atomic_output_retains_previous_snapshot_on_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "ubuntu.json"
            target.write_text('{"previous":true}', encoding="utf-8")
            with self.assertRaises(ValueError):
                oval.write_snapshot(target, {"invalid": float("nan")})
            self.assertEqual(json.loads(target.read_text()), {"previous": True})
            self.assertEqual(list(Path(directory).iterdir()), [target])
            with patch.object(oval, "prepare", side_effect=ValueError("unavailable feed")):
                self.assertEqual(oval.main(["--output", str(target)]), 1)
            self.assertEqual(json.loads(target.read_text()), {"previous": True})
            oval.write_snapshot(target, {"current": True})
            self.assertEqual(json.loads(target.read_text()), {"current": True})


if __name__ == "__main__":
    unittest.main()
