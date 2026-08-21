![version](https://img.shields.io/badge/version-17%2B-3E8B93)
![platform](https://img.shields.io/static/v1?label=platform&message=mac-intel%20|%20mac-arm%20|%20win-64&color=blue)
[![license](https://img.shields.io/github/license/miyako/4d-plugin-pdf-text-extraction)](LICENSE)
![downloads](https://img.shields.io/github/downloads/miyako/4d-plugin-pdf-text-extraction/total)

# 4d-plugin-pdf-text-extraction

Extracts text content from a PDF file on disk and returns it as a 4D `Text` value, using [galkahana/pdf-text-extraction](https://github.com/galkahana/pdf-text-extraction) under the hood. You give it a file path (and, optionally, a page range and a bidi/reading-direction hint); it gives back an object with the extracted text or a failure status.

| Command | Returns | Purpose |
|---|---|---|
| [`PDF Extract text`](#pdf-extract-text) | `Object` | Extract text from a PDF file, optionally restricted to a page range |

**Platforms:** macOS (Intel & Apple Silicon), Windows 64-bit — 4D v17 or later.

---

## Requirements & platform notes

- The plugin exposes a single command, `PDF Extract text`, and it is declared **thread-safe** (per `manifest.json`) — safe to call from a preemptive/worker process.
- **Parameter 1 (`path`) is mandatory.** It's read unconditionally from the parameter list with no presence check before use — omitting it is not a supported call shape.
- **Parameter 2 (`options`) is optional.** The plugin checks whether it was passed before reading anything from it; every field inside it (`start`, `end`, `bidi`) is also individually optional.
- **The command always returns an object**, and that object always has a `success` boolean field. Check `success` before trusting `text` to be present.
- **Failure is reported through the return object, not a 4D error.** There's no 4D-level error/exception raised on a bad path or a corrupt PDF — you must inspect the returned object yourself (see [Error handling](#error-handling--troubleshooting)).
- No behavioral divergence between macOS and Windows was found in this source file — it contains no `#if VERSIONMAC` / `#if VERSIONWIN` branches at all.

---

## PDF Extract text

### Syntax

```4d
PDF Extract text ( path {; options} ) → Object
```

| Parameter | Type | Description |
|---|---|---|
| `path` | Text | Full platform path to the PDF file to read. |
| `options` | Object | Optional. Controls page range and text reading direction — see below. |
| Result | Object | `{success : Boolean; text : Text; status : Longint; error : Text}` — see [Description](#description). |

**`options` object properties** (all optional):

| Property | Type | Description |
|---|---|---|
| `start` | Longint | First page to extract (only applied if greater than `0`; otherwise ignored and extraction starts from the plugin's own default starting point). |
| `end` | Longint | Last page to extract (only applied if greater than or equal to the resolved `start`; otherwise ignored and extraction runs to the plugin's own default end point). |
| `bidi` | Text | Either `"LTR"` or `"RTL"`. Any other value is ignored and the plugin's own default text-direction handling is used. |

### Description

Reads the PDF at `path` and returns its text content as a single `Text` value in `text`, alongside a `success` boolean.

If you omit `options` entirely, or omit `start`/`end`/`bidi` inside it, the command falls back to the underlying extraction library's own defaults for page range and text direction — this doc can't state precisely what those defaults resolve to (e.g. "all pages" vs. some other bound) without the vendored extraction library's own source, which wasn't available at review time. Treat "omit the option" as "let the library decide" rather than assuming a specific page count or direction.

`start` and `end` are only honored if they parse as ordinary finite numbers — if a caller passes something like `1/0`, an out-of-range value, or a non-numeric value that resolves to `NaN`, the plugin ignores it and falls back to its default for that side of the range, rather than passing bad data through.

On success, `text` holds the extracted text and `status` is absent. On failure, `text` is absent (or empty) and `status` holds the extraction library's own internal status code — this is the raw `EStatusCode` value from the vendored library, not a 4D error code, and this doc doesn't have a table of what each numeric value means (that would need the library's own header). If an unexpected internal error occurs during extraction (as opposed to an ordinary "couldn't parse this PDF" failure), the plugin instead returns `success : false` with an `error` field containing a short description — check `error` first if present, then fall back to `status`.

Nothing (warnings or errors) is written back into 4D's own error/console mechanism — any diagnostic detail the underlying library produces beyond `status`/`error` goes to the plugin's own standard error stream, which most 4D setups won't surface to you. Don't expect a 4D `ON ERR CALL` method to fire for a bad PDF path or a corrupt file — check `success` yourself.

### Example

From the plugin's own test method (`TEST.4dm`):

```4d
//%attributes = {}
$path:=Folder:C1567(fk resources folder:K87:11).file("test.pdf").platformPath

$status:=PDF Extract text ($path)

If ($status.success)
	
	$lines:=Split string:C1554($status.text;"\r\n")
	
End if
```

Restricting to a page range and forcing left-to-right reading order:

```4d
$options:=New object
$options.start:=1
$options.end:=5
$options.bidi:="LTR"

$result:=PDF Extract text ($path; $options)

If ($result.success)
	ALERT("Extracted "+String(Length($result.text))+" characters")
Else
	If ($result.error#"")
		ALERT("Extraction failed: "+$result.error)
	Else
		ALERT("Extraction failed, status code: "+String($result.status))
	End if 
End if 
```

Looping over every PDF in a folder and collecting only the ones that succeeded:

```4d
$folder:=Folder(fk documents folder)
$files:=$folder.files("*.pdf")

$extracted:=New collection

For each ($file; $files)
	$r:=PDF Extract text ($file.platformPath)
	If ($r.success)
		$extracted.push($r.text)
	End if 
End for each 
```

---

## Error handling & troubleshooting

- **Always check `success` first.** The command never raises a 4D error on a bad `path`, a missing file, or a corrupt/unreadable PDF — it returns `success : false` instead. Code that assumes `text` exists without checking `success` will fail silently or read a stale/empty value.
- **Prefer `error` over `status` when both could be present.** `error` (present after an internal exception is caught) carries a short human-readable description; `status` is a raw numeric code from the vendored extraction library with no documented mapping in this reference — treat it as a value to log or compare for equality against a known-good run, not as something to branch on by specific number without further investigation.
- **`start`/`end` are silently ignored, not rejected, when malformed.** Passing a non-finite or out-of-range number for either doesn't produce an error — the plugin falls back to its default for that side of the range. If your extracted page range looks wrong, double-check the actual numeric values you're passing in `options` rather than expecting a validation error back.
- **Warnings and non-fatal errors from the underlying library don't reach 4D at all.** They go to the plugin's own standard error stream. If extraction "succeeds" but text looks incomplete or garbled, there may be library-level warnings you currently have no way to see from 4D.
- **`options` fields are all-or-nothing per field, not per-object.** You can pass `options` with only `bidi` set, or only `start`, or any subset — each property is checked independently, so there's no need to fill in every field just because you're passing the object at all.

---

## Quick reference

```4d
// Basic call, whole document, library defaults for direction
$r:=PDF Extract text ($path)
If ($r.success)
	$lines:=Split string($r.text;"\r\n")
End if 

// Page range + explicit reading direction
$options:=New object
$options.start:=1
$options.end:=3
$options.bidi:="RTL"
$r:=PDF Extract text ($path; $options)

// Failure inspection
If (Not($r.success))
	If ($r.error#"")
		// internal exception - see $r.error
	Else
		// ordinary extraction failure - see $r.status
	End if 
End if 
```
