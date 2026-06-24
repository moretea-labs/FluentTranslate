# Data sources and distribution rules

## Bundled Collins COBUILD database

The project currently contains a converted SQLite database derived from the MDX uploaded by the user. The matching MDD has only referenced image assets and is not needed for the plain-text renderer.

This dictionary content is proprietary. It is included for personal local development only. Before public or commercial distribution, remove the database or obtain a suitable licence from HarperCollins.

## ECDICT

ECDICT remains an optional user-installed enrichment source. The app expects `ecdict.sqlite` in `~/Library/Application Support/FluentTranslate/` and merges its Chinese definitions, phonetics and part-of-speech data with the bundled English entry.

## WordNet and CMUdict

These remain possible future open-data additions for semantic relations and phoneme/stress display. The current pronunciation feature uses macOS system speech.

## MDX conversion

`scripts/import_mdict.py` converts unencrypted MDX files into the app's SQLite schema. MDict engine 1.2 dictionaries use LZO compression; the script uses `readmdict` and the MIT-licensed `lzokay` compatibility shim.

A technically readable MDX file does not imply that its dictionary content may be redistributed. File format support and content licensing are separate concerns.
