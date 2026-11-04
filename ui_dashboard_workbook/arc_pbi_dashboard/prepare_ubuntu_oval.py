"""Prepare Canonical USN OVAL reference data for Power Query, using Python's standard library."""

import argparse
import bz2
import calendar
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import re
import sys
import tempfile
import urllib.request
import xml.etree.ElementTree as ET


SUPPORTED_RELEASES = ("noble", "jammy", "focal")
BASE_URL = "https://security-metadata.canonical.com/oval/"
OVAL_NS = "http://oval.mitre.org/XMLSchema/oval-definitions-5"
COMMON_NS = "http://oval.mitre.org/XMLSchema/oval-common-5"
LINUX_NS = OVAL_NS + "#linux"
MAX_COMPRESSED_BYTES = 32 * 1024 * 1024
MAX_XML_BYTES = 256 * 1024 * 1024
CVE_ID = re.compile(r"CVE-\d{4}-\d{4,}")
USN_ID = re.compile(r"USN-\d+-\d+")
PACKAGE_NAME = re.compile(r"[a-z0-9][a-z0-9+.-]*")


def utc_date(value):
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError(f"OVAL timestamp has no timezone: {value!r}")
    return parsed.astimezone(timezone.utc)


def cutoff_date(now):
    year = now.year - 2
    return now.date().replace(year=year, day=min(now.day, calendar.monthrange(year, now.month)[1]))


def child(node, name):
    return node.find(f"{{{OVAL_NS}}}{name}")


def download_feed(url):
    request = urllib.request.Request(url, headers={"User-Agent": "ArcInsights-OVAL/1.0"})
    with urllib.request.urlopen(request, timeout=60) as response:
        if response.status != 200:
            raise ValueError(f"OVAL download returned HTTP {response.status}: {url}")
        data = response.read(MAX_COMPRESSED_BYTES + 1)
    if len(data) > MAX_COMPRESSED_BYTES:
        raise ValueError(f"OVAL download exceeds the compressed size limit: {url}")
    decoder = bz2.BZ2Decompressor()
    xml = decoder.decompress(data, max_length=MAX_XML_BYTES + 1)
    if len(xml) > MAX_XML_BYTES or not decoder.eof or decoder.unused_data:
        raise ValueError(f"OVAL download is oversized, truncated or contains trailing data: {url}")
    return xml, hashlib.sha256(data).hexdigest()


def package_targets(test, objects, states, variables):
    if test.tag != f"{{{LINUX_NS}}}dpkginfo_test":
        return None
    if test.get("check", "all") not in ("all", "at least one"):
        return None
    if test.get("check_existence", "at_least_one_exists") not in (
        "at_least_one_exists", "all_exist", "any_exist",
    ):
        return None
    object_refs = test.findall(f"{{{LINUX_NS}}}object")
    state_refs = test.findall(f"{{{LINUX_NS}}}state")
    if len(object_refs) != 1 or len(state_refs) != 1:
        return None
    obj = objects[object_refs[0].attrib["object_ref"]]
    state = states[state_refs[0].attrib["state_ref"]]
    if obj.tag != f"{{{LINUX_NS}}}dpkginfo_object" or state.tag != f"{{{LINUX_NS}}}dpkginfo_state":
        return None
    names = obj.findall(f"{{{LINUX_NS}}}name")
    evrs = state.findall(f"{{{LINUX_NS}}}evr")
    if len(names) != 1 or len(evrs) != 1 or len(state) != 1:
        return None
    name = names[0]
    evr = evrs[0]
    if name.get("operation", "equals") != "equals":
        return None
    if evr.get("operation") != "less than" or evr.get("datatype") != "debian_evr_string":
        return None
    version = (evr.text or "").strip()
    if not version or any(c.isspace() for c in version):
        raise ValueError(f"Invalid fixed package version in {state.get('id')}")
    variable_ref = name.get("var_ref")
    if variable_ref:
        variable = variables[variable_ref]
        if variable.tag != f"{{{OVAL_NS}}}constant_variable" or variable.get("datatype") != "string":
            return None
        values = [(node.text or "").strip() for node in variable.findall(f"{{{OVAL_NS}}}value")]
    else:
        values = [(name.text or "").strip()]
    if not values or any(not PACKAGE_NAME.fullmatch(value) for value in values):
        raise ValueError(f"Invalid binary package names in {obj.get('id')}")
    return [{"name": value, "version": version, "is_source": False} for value in sorted(set(values))]


def parse_feed(xml, release, now):
    if release not in SUPPORTED_RELEASES:
        raise ValueError(f"Unsupported Ubuntu release: {release}")
    if b"<!DOCTYPE" in xml or b"<!ENTITY" in xml:
        raise ValueError("OVAL must not contain a DTD or entity declarations")
    root = ET.fromstring(xml)
    if root.tag != f"{{{OVAL_NS}}}oval_definitions":
        raise ValueError("Expected an OVAL definitions document")
    sections = {}
    for name in ("generator", "definitions", "tests", "objects", "states", "variables"):
        section = child(root, name)
        if section is None:
            raise ValueError(f"OVAL document is missing {name}")
        sections[name] = section
    timestamp = sections["generator"].find(f"{{{COMMON_NS}}}timestamp")
    if timestamp is None or not timestamp.text:
        raise ValueError("OVAL generator timestamp is missing")
    generated = datetime.fromisoformat(timestamp.text.replace("Z", "+00:00"))
    if generated.tzinfo is not None and (generated - now).total_seconds() > 600:
        raise ValueError("OVAL generator timestamp is in the future")
    indexes = {}
    for name in ("tests", "objects", "states", "variables"):
        nodes = list(sections[name])
        indexes[name] = {node.attrib["id"]: node for node in nodes}
        if len(indexes[name]) != len(nodes):
            raise ValueError(f"Duplicate OVAL identifiers in {name}")
    notices = []
    cves = {}
    omitted = {}
    omitted_definitions = {}
    for definition in sections["definitions"]:
        if definition.get("class") != "patch":
            continue
        metadata = child(definition, "metadata")
        if metadata is None:
            raise ValueError("Patch definition has no metadata")
        advisory = child(metadata, "advisory")
        issued = None if advisory is None else child(advisory, "issued")
        if issued is None or not issued.get("date"):
            raise ValueError(f"Patch definition has no publication date: {definition.get('id')}")
        published = utc_date(issued.attrib["date"])
        if published.date() < cutoff_date(now):
            continue
        references = metadata.findall(f"{{{OVAL_NS}}}reference")
        notice_ids = {ref.attrib["ref_id"] for ref in references if ref.get("source") == "USN"}
        if not notice_ids and any(ref.get("source") == "LSN" for ref in references):
            omitted_definitions["livepatch"] = omitted_definitions.get("livepatch", 0) + 1
            continue
        if len(notice_ids) != 1 or not USN_ID.fullmatch(next(iter(notice_ids))):
            raise ValueError(f"Patch definition has no unique USN: {definition.get('id')}")
        notice_id = next(iter(notice_ids))
        cve_ids = {ref.attrib["ref_id"] for ref in references if ref.get("source") == "CVE"}
        if any(not CVE_ID.fullmatch(value) for value in cve_ids):
            raise ValueError(f"Patch definition has invalid CVE references: {notice_id}")
        ratings = {}
        for node in advisory.findall(f"{{{OVAL_NS}}}cve"):
            identifier = (node.text or "").strip()
            if identifier not in cve_ids:
                raise ValueError(f"Unreferenced CVE rating in {notice_id}: {identifier}")
            raw_score = (node.get("cvss_score") or "").strip()
            vector = (node.get("cvss_vector") or "").strip()
            score = None
            version = None
            if raw_score:
                if vector.startswith(("CVSS:3.0/", "CVSS:3.1/")):
                    version = "3"
                elif vector.startswith("CVSS:4.0/"):
                    version = "4"
                else:
                    raise ValueError(f"CVSS score has no supported versioned vector: {identifier}")
                score = float(raw_score)
                if not math.isfinite(score) or not 0 <= score <= 10:
                    raise ValueError(f"Invalid CVSS score: {identifier}")
            ratings[identifier] = {
                "id": identifier,
                "priority": node.get("priority"),
                "cvss_score": score,
                "cvss_version": version,
            }
        for identifier in sorted(cve_ids):
            rating = ratings.get(identifier, {
                "id": identifier, "priority": None, "cvss_score": None, "cvss_version": None,
            })
            previous = cves.get(identifier)
            if previous is not None and previous != rating:
                raise ValueError(f"Inconsistent CVE ratings in the OVAL feed: {identifier}")
            cves[identifier] = rating
        packages = {}

        def walk(criteria, negated=False):
            negated = negated or criteria.get("negate", "false").lower() == "true"
            for node in criteria:
                if node.tag == f"{{{OVAL_NS}}}criteria":
                    walk(node, negated)
                elif node.tag == f"{{{OVAL_NS}}}criterion":
                    test_id = node.attrib["test_ref"]
                    test = indexes["tests"][test_id]
                    targets = None if negated or node.get("negate", "false").lower() == "true" else package_targets(
                        test, indexes["objects"], indexes["states"], indexes["variables"]
                    )
                    if targets is None:
                        reason = test.tag.rsplit("}", 1)[-1]
                        omitted[reason] = omitted.get(reason, 0) + 1
                    else:
                        for target in targets:
                            packages[(target["name"], target["version"])] = target
                elif node.tag == f"{{{OVAL_NS}}}extend_definition":
                    omitted["extend_definition"] = omitted.get("extend_definition", 0) + 1

        criteria = child(definition, "criteria")
        if criteria is None:
            raise ValueError(f"Patch definition has no criteria: {notice_id}")
        walk(criteria)
        title = child(metadata, "title")
        notices.append({
            "id": notice_id,
            "title": "" if title is None else (title.text or "").strip(),
            "published": published.isoformat().replace("+00:00", "Z"),
            "cves_ids": sorted(cve_ids),
            "release_packages": {release: list(packages.values())},
        })
    if not notices:
        raise ValueError(f"No recent patch definitions found for {release}")
    return {
        "notices": sorted(notices, key=lambda item: (item["published"], item["id"]), reverse=True),
        "cves": cves,
        "generator_timestamp": generated.isoformat().replace("+00:00", "Z"),
        "unsupported_test_counts": omitted,
        "unsupported_definition_counts": omitted_definitions,
    }


def prepare(releases, now, fetch=download_feed):
    notices = {}
    ratings = {}
    sources = []
    for release in releases:
        if release not in SUPPORTED_RELEASES:
            raise ValueError(f"Unsupported Ubuntu release: {release}")
        url = f"{BASE_URL}com.ubuntu.{release}.usn.oval.xml.bz2"
        xml, digest = fetch(url)
        data = parse_feed(xml, release, now)
        notices[release] = data["notices"]
        for identifier, rating in data["cves"].items():
            if identifier in ratings and ratings[identifier] != rating:
                raise ValueError(f"Inconsistent CVE ratings across releases: {identifier}")
            ratings[identifier] = rating
        sources.append({
            "release": release,
            "url": url,
            "sha256": digest,
            "generator_timestamp": data["generator_timestamp"],
            "unsupported_test_counts": data["unsupported_test_counts"],
            "unsupported_definition_counts": data["unsupported_definition_counts"],
        })
        if data["unsupported_test_counts"]:
            print(f"WARNING: {release}: complex OVAL tests are not evaluated; unmatched patches remain uncovered: "
                  f"{json.dumps(data['unsupported_test_counts'], sort_keys=True)}", file=sys.stderr)
        if data["unsupported_definition_counts"]:
            print(f"WARNING: {release}: definitions outside binary-package update mapping are not evaluated: "
                  f"{json.dumps(data['unsupported_definition_counts'], sort_keys=True)}", file=sys.stderr)
    return {
        "schema_version": 1,
        "generated_at": now.isoformat().replace("+00:00", "Z"),
        "sources": sources,
        "notices": notices,
        "cves": ratings,
    }


def write_snapshot(path, document):
    path = Path(path).expanduser().resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent, delete=False) as handle:
            temporary = Path(handle.name)
            json.dump(document, handle, separators=(",", ":"), allow_nan=False)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True, help="Local JSON snapshot to create or atomically replace.")
    parser.add_argument("--releases", nargs="+", choices=SUPPORTED_RELEASES, default=list(SUPPORTED_RELEASES))
    args = parser.parse_args(argv)
    try:
        document = prepare(list(dict.fromkeys(args.releases)), datetime.now(timezone.utc))
        write_snapshot(args.output, document)
    except (OSError, ValueError, KeyError, ET.ParseError) as error:
        print(f"ERROR: Ubuntu OVAL preparation failed; the previous snapshot was not replaced: {error}", file=sys.stderr)
        return 1
    print(f"Prepared {sum(len(rows) for rows in document['notices'].values())} notices and "
          f"{len(document['cves'])} CVEs in {args.output.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
