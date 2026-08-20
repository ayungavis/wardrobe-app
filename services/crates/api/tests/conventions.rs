use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

// ----------------------------------------------------------------- discovery

fn crates_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .canonicalize()
        .expect("crates/ sits one level above this crate")
}

fn rust_files(root: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    let mut stack = vec![root.to_path_buf()];
    while let Some(dir) = stack.pop() {
        for entry in fs::read_dir(&dir).expect("a readable directory") {
            let path = entry.expect("a readable entry").path();
            if path.is_dir() {
                if path.file_name().is_some_and(|name| name == "target") {
                    continue;
                }
                stack.push(path);
            } else if path.extension().is_some_and(|ext| ext == "rs") {
                out.push(path);
            }
        }
    }
    out.sort();
    out
}

fn at(root: &Path, path: &Path, line: usize) -> String {
    let short = path.strip_prefix(root).unwrap_or(path);
    format!("crates/{}:{}", short.display(), line)
}

fn report(rule: &str, found: &[String]) -> String {
    let mut out = format!("\n{} violation(s) of: {rule}\n", found.len());
    for one in found {
        out.push_str("  ");
        out.push_str(one);
        out.push('\n');
    }
    out
}

#[derive(PartialEq, Eq, Clone, Copy)]
enum Comment {
    Inner,
    Doc,
    Plain,
    Code,
}

fn classify(line: &str) -> Comment {
    let text = line.trim_start();
    if text.starts_with("//!") {
        Comment::Inner
    } else if text.starts_with("////") {
        Comment::Code
    } else if text.starts_with("///") {
        Comment::Doc
    } else if text.starts_with("//") {
        Comment::Plain
    } else {
        Comment::Code
    }
}

fn body(line: &str) -> &str {
    line.trim_start().trim_start_matches('/').trim()
}

// ------------------------------------------------------------------ C1 comments

#[test]
fn every_comment_belongs_to_a_category_the_rules_allow() {
    let root = crates_root();
    let mut found = Vec::new();
    for path in rust_files(&root) {
        let text = fs::read_to_string(&path).expect("a readable source file");
        let lines: Vec<&str> = text.lines().collect();
        let mut i = 0;
        while i < lines.len() {
            let kind = classify(lines[i]);
            if kind == Comment::Code {
                i += 1;
                continue;
            }
            let start = i;
            while i < lines.len() && classify(lines[i]) == kind {
                i += 1;
            }
            let head = body(lines[start]);
            let span = i - start;
            let here = at(&root, &path, start + 1);
            match kind {
                Comment::Inner => found.push(format!("{here}  `//!` module doc; the rules allow none")),
                Comment::Doc if span > 1 && head != "# Errors" && head != "# Panics" => found.push(
                    format!("{here}  doc comment spans {span} lines; only its first line reaches openapi.json"),
                ),
                Comment::Doc if span == 1 && head.is_empty() => {
                    found.push(format!("{here}  empty doc comment"));
                }
                Comment::Plain
                    if !(head.starts_with("clippy:")
                        || head.starts_with("ponytail:")
                        || head.starts_with("SAFETY:")
                        || head.starts_with("---")) =>
                {
                    found.push(format!("{here}  prose; say it in the reply, not the file"));
                }
                _ => {}
            }
        }
    }
    assert!(
        found.is_empty(),
        "{}",
        report(
            "a comment starts with clippy:, ponytail:, SAFETY:, or ---; a doc comment is one line or a clippy section",
            &found
        )
    );
}

// ------------------------------------------------------------------ C2 allows

#[test]
fn every_allow_names_the_shortcut_it_takes() {
    let root = crates_root();
    let mut found = Vec::new();
    for path in rust_files(&root) {
        let text = fs::read_to_string(&path).expect("a readable source file");
        let lines: Vec<&str> = text.lines().collect();
        for (n, line) in lines.iter().enumerate() {
            let text = line.trim_start();
            if !(text.starts_with("#[allow(") || text.starts_with("#![allow(")) {
                continue;
            }
            let mut top = n;
            while top > 0 && classify(lines[top - 1]) == Comment::Plain {
                top -= 1;
            }
            let marked = top < n && {
                let head = body(lines[top]);
                head.starts_with("clippy:") || head.starts_with("ponytail:")
            };
            if !marked {
                found.push(format!("{}  {text}", at(&root, &path, n + 1)));
            }
        }
    }
    assert!(
        found.is_empty(),
        "{}",
        report(
            "an allow carries a `// clippy:` or `// ponytail:` line above it saying why",
            &found
        )
    );
}

// ------------------------------------------------------------------- C3 traits

#[test]
fn the_backend_declares_no_traits() {
    let root = crates_root();
    let mut found = Vec::new();
    for path in rust_files(&root) {
        if !path.components().any(|part| part.as_os_str() == "src") {
            continue;
        }
        let text = fs::read_to_string(&path).expect("a readable source file");
        for (n, line) in text.lines().enumerate() {
            let text = line.trim_start();
            if text.starts_with("trait ")
                || text.starts_with("pub trait ")
                || text.starts_with("pub(crate) trait ")
            {
                found.push(format!("{}  {text}", at(&root, &path, n + 1)));
            }
        }
    }
    assert!(
        found.is_empty(),
        "{}",
        report(
            "a trait exists only for a dependency CI cannot run for real; add it to this test's allowlist deliberately",
            &found
        )
    );
}

// -------------------------------------------------------------------- C4 names

#[test]
fn no_two_sibling_modules_differ_only_by_a_plural_s() {
    let root = crates_root();
    let mut by_dir: BTreeMap<PathBuf, Vec<String>> = BTreeMap::new();
    for path in rust_files(&root) {
        let dir = path.parent().expect("a file has a parent").to_path_buf();
        let stem = path
            .file_stem()
            .expect("a .rs file has a stem")
            .to_string_lossy()
            .into_owned();
        by_dir.entry(dir).or_default().push(stem);
    }
    let mut found = Vec::new();
    for (dir, stems) in by_dir {
        for stem in &stems {
            if stems.contains(&format!("{stem}s")) {
                let short = dir.strip_prefix(&root).unwrap_or(&dir);
                found.push(format!(
                    "crates/{}/  {stem}.rs and {stem}s.rs",
                    short.display()
                ));
            }
        }
    }
    assert!(
        found.is_empty(),
        "{}",
        report(
            "two module names one letter apart are a mis-import waiting to happen",
            &found
        )
    );
}
