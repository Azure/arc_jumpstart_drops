(requiredReleases as list) as record =>
let
    Url = "https://raw.githubusercontent.com/chrisdoofer/arc-sql-agent/refs/heads/ubuntu-oval-data/ubuntu-usn-oval.json",
    Read = try Json.Document(Binary.Buffer(Web.Contents("https://raw.githubusercontent.com", [RelativePath = "chrisdoofer/arc-sql-agent/refs/heads/ubuntu-oval-data/ubuntu-usn-oval.json", Timeout = #duration(0, 0, 2, 0)]))),
    Payload = if Read[HasError] then error Error.Record("UbuntuOvalReadFailed", "Cannot download the Ubuntu OVAL reference. Check network access, Anonymous credentials and the repository's Publish Ubuntu OVAL reference workflow; no local JSON preparation is required.", [Url = Url, Cause = Read[Error]]) else Read[Value],
    Invalid = (message as text) => error Error.Record("UbuntuOvalSnapshotInvalid", message & " The reference publisher must regenerate a valid snapshot; check the publishing workflow.", [Url = Url]),
    Schema = if not Value.Is(Payload, type record) then Invalid("Expected an OVAL snapshot record.")
        else if not Record.HasFields(Payload, {"schema_version", "generated_at", "sources", "notices", "cves"}) then Invalid("Required snapshot fields are missing.")
        else if Payload[schema_version] <> 1 or not Value.Is(Payload[generated_at], type text)
            or not Value.Is(Payload[sources], type list) or not Value.Is(Payload[notices], type record)
            or not Value.Is(Payload[cves], type record) then Invalid("Unsupported OVAL snapshot schema.")
        else Payload,
    ParseDate = (value as any) as datetimezone =>
        if not Value.Is(value, type text) then Invalid("Expected a UTC timestamp.")
        else if not Text.EndsWith(value, "Z") then Invalid("Expected a UTC timestamp ending in Z.")
        else let Parsed = try DateTimeZone.FromText(value)
            in if Parsed[HasError] then Invalid("An OVAL timestamp is invalid.") else Parsed[Value],
    Generated = ParseDate(Schema[generated_at]),
    AgeHours = Duration.TotalHours(DateTimeZone.FixedUtcNow() - Generated),
    Fresh = if AgeHours < -1 / 6 then Invalid("The snapshot generation time is in the future.")
        else if AgeHours > 24 then error Error.Record("UbuntuOvalSnapshotStale", "The published Ubuntu OVAL reference is more than 24 hours old. The publisher must restore the scheduled feed; check the repository's Publish Ubuntu OVAL reference workflow.", [Url = Url, GeneratedAt = Schema[generated_at]])
        else true,
    CheckPackage = (package as any) as logical =>
        if not Value.Is(package, type record) then Invalid("Expected a binary-package record.")
        else if not Record.HasFields(package, {"name", "version", "is_source"}) then Invalid("A package record is incomplete.")
        else if not Value.Is(package[name], type text) or not Value.Is(package[version], type text)
            or package[is_source] <> false then Invalid("A package target is invalid.")
        else if Text.Trim(package[name]) = "" or Text.Trim(package[version]) = "" then Invalid("A package target is empty.")
        else true,
    CheckNotice = (notice as any, release as text) as logical =>
        if not Value.Is(notice, type record) then Invalid("Expected a notice record.")
        else if not Record.HasFields(notice, {"id", "title", "published", "cves_ids", "release_packages"}) then Invalid("A notice record is incomplete.")
        else if not Value.Is(notice[id], type text) or not Value.Is(notice[title], type text)
            or not Value.Is(notice[cves_ids], type list) or not Value.Is(notice[release_packages], type record) then Invalid("A notice record has invalid field types.")
        else if not Text.StartsWith(notice[id], "USN-") or not Record.HasFields(notice[release_packages], release) then Invalid("A notice has an invalid identifier or release.")
        else
            let
                Published = ParseDate(notice[published]),
                Packages = Record.Field(notice[release_packages], release),
                CvesReady = List.AllTrue(List.Transform(notice[cves_ids], each if not Value.Is(_, type text) then Invalid("Expected a CVE identifier.") else if not Text.StartsWith(_, "CVE-") then Invalid("Invalid CVE identifier.") else true))
            in
                if not Value.Is(Packages, type list) then Invalid("Expected a list of binary-package targets.")
                else Published <= DateTimeZone.FixedUtcNow() and CvesReady and List.AllTrue(List.Transform(Packages, each CheckPackage(_))),
    Releases = List.Buffer(List.Distinct(requiredReleases)),
    CheckRelease = (release as text) as list =>
        let
            Notices = if Record.HasFields(Schema[notices], release) then Record.Field(Schema[notices], release)
                else error Error.Record("UbuntuOvalReleaseMissing", "The published OVAL reference does not contain a required Ubuntu release. The publisher must include all supported releases.", [Url = Url, Release = release]),
            Sources = List.Select(Schema[sources], each
                if not Value.Is(_, type record) then Invalid("Expected an OVAL source manifest record.")
                else if not Record.HasFields(_, {"release", "url", "sha256", "generator_timestamp", "unsupported_test_counts", "unsupported_definition_counts"}) then Invalid("An OVAL source manifest is incomplete.")
                else [release] = release),
            SourceReady = if List.Count(Sources) <> 1 then Invalid("Expected exactly one source manifest per requested release.")
                else Sources{0}[url] = "https://security-metadata.canonical.com/oval/com.ubuntu." & release & ".usn.oval.xml.bz2"
                    and Value.Is(Sources{0}[sha256], type text) and Text.Length(Sources{0}[sha256]) = 64
                    and Value.Is(Sources{0}[unsupported_test_counts], type record)
                    and Value.Is(Sources{0}[unsupported_definition_counts], type record),
            Checked = if not Value.Is(Notices, type list) then Invalid("Expected an OVAL notice list.")
                else if not SourceReady or List.IsEmpty(Notices) then Invalid("The release source manifest or notice list is invalid.")
                else if List.AllTrue(List.Transform(Notices, each CheckNotice(_, release))) then Notices
                else Invalid("A notice contains an invalid publication date."),
            Cutoff = Date.AddMonths(Date.From(DateTimeZone.FixedUtcNow()), -24)
        in List.Buffer(List.Select(Checked, each Date.From(ParseDate([published])) >= Cutoff)),
    NoticesByRelease = Record.FromList(List.Transform(Releases, each CheckRelease(_)), Releases),
    NoticesReady = List.AllTrue(List.Transform(Releases, each List.Count(Record.Field(NoticesByRelease, _)) >= 0))
in
    if Fresh and NoticesReady then Record.Combine({Schema, [notices = NoticesByRelease]})
    else Invalid("The OVAL snapshot did not pass validation.")
