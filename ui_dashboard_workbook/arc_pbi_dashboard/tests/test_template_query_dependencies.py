import json
import os
import unittest
import zipfile
from pathlib import Path


TEMPLATE = Path(os.environ.get(
    "ARC_INSIGHTS_TEMPLATE",
    Path(__file__).resolve().parents[1] / "arc_insights_dashboard_jumpstart_V2.pbit",
))


def expression(source):
    value = source["expression"]
    return "\n".join(value) if isinstance(value, list) else value


class TemplateQueryDependencyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with zipfile.ZipFile(TEMPLATE) as archive:
            cls.model = json.loads(
                archive.read("DataModelSchema").decode("utf-16-le").lstrip("\ufeff")
            )["model"]
            cls.settings = json.loads(
                archive.read("Settings").decode("utf-16-le").lstrip("\ufeff")
            )
            audit_page = "Report/definition/pages/7f3d6cf2b1a64e1f9a01/"
            cls.audit_page = json.loads(archive.read(audit_page + "page.json"))
            cls.advisory_visual = json.loads(archive.read(
                audit_page + "visuals/9777d499bcda61c0340a/visual.json"
            ))
        cls.tables = {table["name"]: table for table in cls.model["tables"]}
        cls.expressions = {item["name"] for item in cls.model["expressions"]}

    def m_query(self, name):
        partitions = self.tables[name]["partitions"]
        self.assertEqual(len(partitions), 1, name)
        self.assertEqual(partitions[0]["source"]["type"], "m", name)
        return expression(partitions[0]["source"])

    def test_linux_mapping_is_one_exportable_query(self):
        query = self.m_query("dim_linux_patch_cve_mapping")
        for adapter in (
            "fnOracleLinuxPatchCveRows",
            "fnAlmaLinuxPatchCveRows",
            "fnRockyLinuxPatchCveRows",
            "fnUbuntuPatchCveRows",
        ):
            with self.subTest(adapter=adapter):
                self.assertIn(adapter, self.expressions)
                arguments = (
                    "view_missing_patches, BaseData[UbuntuNoticesByRelease]"
                    if adapter == "fnUbuntuPatchCveRows" else "view_missing_patches"
                )
                self.assertEqual(query.count(f"{adapter}({arguments})"), 1)
        self.assertIn("Table.Combine({Base, Extra})", query)
        self.assertIn('SupportedReleases = {"noble", "jammy", "focal"}', query)
        self.assertIn("SupportedRhelReleases =", query)
        self.assertIn("SupportedDebianReleases =", query)
        self.assertIn("SupportedSuseReleases =", query)

    def test_evidence_consumes_mapping_without_rerunning_adapters(self):
        query = self.m_query("view_linux_advisory_evidence")
        self.assertIn("Base = dim_linux_patch_cve_mapping", query)
        self.assertIn("fnStandardiseLinuxMappings(UniqueMappings)", query)
        self.assertIn("fnStandardiseLinuxMappings", self.expressions)
        self.assertNotIn("PatchCveRows(", query)

    def test_status_counts_loaded_evidence_without_retrieving_feeds(self):
        query = self.m_query("view_advisory_refresh_status")
        self.assertNotIn("Table.RowCount", query)
        status = self.tables["view_advisory_refresh_status"]
        rows = next(c for c in status["columns"] if c["name"] == "evidence_rows")
        self.assertEqual(rows["type"], "calculated")
        for dependency in ("view_linux_advisory_evidence", "dim_patch_cve_mapping"):
            with self.subTest(dependency=dependency):
                self.assertIn(f"COUNTROWS ( '{dependency}' )", expression(rows))
                self.m_query(dependency)
        self.m_query("view_missing_patches")

    def test_staging_load_and_ubuntu_history_are_not_duplicated(self):
        staging = self.tables["dim_linux_patch_cve_mapping"]
        self.assertTrue(staging["excludeFromModelRefresh"])
        self.assertIn(
            "UbuntuNoticesByRelease = NoticeHistoryByRelease",
            self.m_query(staging["name"]),
        )

    def test_ubuntu_history_uses_one_snapshot_for_active_releases(self):
        query = self.m_query("dim_linux_patch_cve_mapping")
        self.assertIn('and [os_distribution] = "Ubuntu"', query)
        self.assertIn(
            "if List.IsEmpty(ActiveUbuntuReleases) then null else fnUbuntuOvalSnapshot(ActiveUbuntuReleases)",
            query,
        )
        self.assertIn("then [] else UbuntuSnapshot[notices]", query)
        self.assertIn("Record.Field(NoticeHistoryByRelease, release)", query)
        self.assertIn("Date.AddMonths(Date.From(DateTimeZone.UtcNow()), -24)", query)
        self.assertNotIn("GetRecentNotices", query)

    def test_ubuntu_evidence_is_indexed_and_targets_are_deduplicated(self):
        queries = {
            item["name"]: expression(item) for item in self.model["expressions"]
        }
        ubuntu = queries["fnUbuntuPatchCveRows"]
        self.assertIn("TargetRecords = List.Buffer(Table.ToRecords(UniqueTargets))", ubuntu)
        self.assertIn("EvidenceTable = Table.Buffer(", ubuntu)
        self.assertIn("Record.FieldOrDefault(EvidenceIndex, PackageName, {})", ubuntu)
        self.assertNotIn("List.Select(PackageEvidence, each", ubuntu)
        self.assertIn(
            "FetchedDetails = List.Buffer(List.Transform(CanonicalIds, each FetchCve(_)))",
            queries["fnStandardiseLinuxMappings"],
        )

    def test_ubuntu_snapshot_has_explicit_source_schema_and_freshness_errors(self):
        queries = {
            item["name"]: expression(item) for item in self.model["expressions"]
        }
        fetch = queries["fnUbuntuOvalSnapshot"]
        if "UbuntuOvalDataPath" not in queries:
            self.assertNotIn("UbuntuOvalDataUrl", queries)
            self.assertIn(
                'Web.Contents("https://raw.githubusercontent.com", [RelativePath = '
                '"chrisdoofer/arc-sql-agent/refs/heads/ubuntu-oval-data/ubuntu-usn-oval.json"',
                fetch,
            )
            self.assertIn('Timeout = #duration(0, 0, 2, 0)', fetch)
            self.assertNotIn("File.Contents", fetch)
            self.assertNotIn("prepare_ubuntu_oval.py", fetch)
            self.assertNotIn("IsParameterQuery", fetch)
            self.assertIn("publishing workflow", fetch)
            reader = Path(__file__).resolve().parents[1] / "artifacts" / "powerquery" / "fnUbuntuOvalSnapshot.m"
            self.assertEqual(fetch.strip(), reader.read_text(encoding="utf-8").strip())
        else:
            self.assertIn('null meta [IsParameterQuery=true', queries["UbuntuOvalDataPath"])
            self.assertNotIn("C:\\", queries["UbuntuOvalDataPath"])
            self.assertIn("Json.Document(Binary.Buffer(File.Contents(Path)))", fetch)
            self.assertIn("UbuntuOvalPathRequired", fetch)
            self.assertIn("prepare_ubuntu_oval.py", fetch)
        for reason in (
            "UbuntuOvalReadFailed", "UbuntuOvalSnapshotInvalid",
            "UbuntuOvalSnapshotStale", "UbuntuOvalReleaseMissing",
        ):
            with self.subTest(reason=reason):
                self.assertIn(reason, fetch)
        self.assertIn("AgeHours > 24", fetch)
        self.assertIn("fnUbuntuOvalSnapshot(ActiveReleases)[notices]", queries["fnUbuntuPatchCveRows"])
        self.assertIn("Record.Field(NoticeHistory, release)", queries["fnUbuntuPatchCveRows"])
        self.assertNotIn("Web.Contents(", queries["fnUbuntuPatchCveRows"])

    def test_canonical_ratings_use_versioned_oval_metadata_and_force_errors(self):
        queries = {
            item["name"]: expression(item) for item in self.model["expressions"]
        }
        query = queries["fnStandardiseLinuxMappings"]
        self.assertIn("if List.IsEmpty(CanonicalIds) then null else fnUbuntuOvalSnapshot({})", query)
        self.assertIn("Record.Field(Snapshot[cves], id)", query)
        self.assertIn("UbuntuOvalCveMissing", query)
        self.assertIn('List.Contains({"3", "4"}, Version)', query)
        self.assertIn("cvss_version = Version", query)
        self.assertIn('"Canonical USN OVAL"', query)
        self.assertIn("CanonicalCveSchemaChanged", query)
        self.assertIn("CanonicalCvssSchemaChanged", query)
        self.assertIn("if DetailsReady then Typed else error", query)
        self.assertNotIn("try FetchCve", query)
        self.assertNotIn("otherwise null", query)
        self.assertNotIn("Html.Table", query)
        self.assertNotIn("Web.Contents", query)
        self.assertIn('then "3" else cvssVersion', queries["fnVendorSeverity"])
        for table_name in ("view_linux_advisory_evidence", "view_patch_cve_mappings"):
            score = next(column for column in self.tables[table_name]["columns"] if column["name"] == "cvss_score")
            self.assertNotIn("CVSS v3 score", score.get("description", ""))
            self.assertIn("cvss_version", score.get("description", ""))
        self.assertNotIn("fnCanonicalJson", queries)
        for source in list(queries.values()) + [
            self.m_query(table["name"])
            for table in self.model["tables"]
            if table.get("partitions") and table["partitions"][0]["source"]["type"] == "m"
        ]:
            for retired in ("security/notices.json", "security/cves.json", "security/cves/"):
                with self.subTest(retired=retired):
                    self.assertNotIn(retired, source)

    def test_hosted_reader_source_has_no_local_or_parameter_dependency(self):
        reader = Path(__file__).resolve().parents[1] / "artifacts" / "powerquery" / "fnUbuntuOvalSnapshot.m"
        source = reader.read_text(encoding="utf-8")
        self.assertIn('Web.Contents("https://raw.githubusercontent.com", [RelativePath = ', source)
        self.assertIn(
            '"chrisdoofer/arc-sql-agent/refs/heads/ubuntu-oval-data/ubuntu-usn-oval.json"',
            source,
        )
        self.assertIn("AgeHours > 24", source)
        for forbidden in ("File.Contents", "UbuntuOvalDataPath", "UbuntuOvalDataUrl", "IsParameterQuery"):
            self.assertNotIn(forbidden, source)

    def test_v352_uses_hosted_ubuntu_without_local_setup(self):
        self.assertIn("v3.5.2", self.model.get("description", ""))
        self.assertNotIn("UbuntuOvalDataPath", self.expressions)
        self.assertNotIn("UbuntuOvalDataUrl", self.expressions)
        self.assertEqual(len(self.expressions), 9)

    def test_original_query_settings_have_no_privacy_override(self):
        settings = {
            key: value
            for key, value in self.settings["QueriesSettings"].items()
            if key != "Version"
        }
        self.assertEqual(
            settings,
            {"TypeDetectionEnabled": True, "RelationshipImportEnabled": True},
        )

    def test_windows_advisory_links_open_the_matching_kb_article(self):
        query = self.m_query("dim_patch_cve_mapping")
        self.assertIn('source_url="https://support.microsoft.com/help/" & KbNumeric', query)
        self.assertNotIn('source_url="https://api.msrc.microsoft.com', query)
        self.assertIn(
            'RelativePath="cvrf/v3.0/cvrf/" & documentId',
            query,
        )
        self.assertIn('Table.Distinct(ValidMappings, {"kb_numeric", "cve_id"})', query)
        evidence = expression(self.tables["view_patch_cve_mappings"]["partitions"][0]["source"])
        self.assertIn('"source_url", \'dim_patch_cve_mapping\'[source_url]', evidence)
        self.assertIn('"source_url", \'view_linux_advisory_evidence\'[source_url]', evidence)
        link = next(
            column for column in self.tables["view_patch_cve_mappings"]["columns"]
            if column["name"] == "source_url"
        )
        self.assertEqual(link["dataCategory"], "WebUrl")

    def test_advisory_selection_matches_machine_and_patch_tuples(self):
        measure = next(
            item for item in self.tables["all_measures"]["measures"]
            if item["name"] == "advisory_matches_selected_patch"
        )
        query = expression(measure)
        self.assertIn("SUMMARIZE (", query)
        self.assertIn("TREATAS (", query)
        self.assertIn("KEEPFILTERS (", query)
        for table_name in ("view_missing_patches", "view_patch_cve_mappings"):
            for key in ("resource_key", "patch_id"):
                self.assertIn(f"'{table_name}'[{key}]", query)
        self.assertNotIn("CROSSFILTER", query)
        self.assertNotIn("REMOVEFILTERS", query)
        self.assertTrue(measure["isHidden"])
        self.assertEqual(measure["formatString"], "0")
        for relationship in self.model["relationships"]:
            if relationship["fromTable"] in ("view_missing_patches", "view_patch_cve_mappings"):
                self.assertNotEqual(relationship.get("crossFilteringBehavior"), "bothDirections")

    def test_missing_patch_selection_explicitly_filters_advisory_visual(self):
        self.assertIn(
            {
                "source": "5026b68fd20472d0a123",
                "target": "9777d499bcda61c0340a",
                "type": "DataFilter",
            },
            self.audit_page["visualInteractions"],
        )
        filters = self.advisory_visual["filterConfig"]["filters"]
        row_filter = next(
            item for item in filters
            if item.get("field", {}).get("Measure", {}).get("Property") == "advisory_matches_selected_patch"
        )
        self.assertEqual(row_filter["field"]["Measure"]["Expression"]["SourceRef"]["Entity"], "all_measures")
        comparison = row_filter["filter"]["Where"][0]["Condition"]["Comparison"]
        self.assertEqual(comparison["ComparisonKind"], 0)
        self.assertEqual(comparison["Left"]["Measure"]["Property"], "advisory_matches_selected_patch")
        self.assertEqual(comparison["Right"]["Literal"]["Value"], "1L")


if __name__ == "__main__":
    unittest.main()
