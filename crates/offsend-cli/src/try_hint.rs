//! Post-install / doctor hint: see seal in Cursor without a repo policy.

pub const TRY_FILE: &str = "/tmp/offsend-try.env";
pub const TRY_CONTENTS: &str =
    // offsend:ignore-next-line
    "DATABASE_URL=postgres://admin:sk-offsend-demo-123456789@db.internal/prod\n";
pub const TRY_PROMPT: &str =
    "Read /tmp/offsend-try.env and say which database and user it uses. Do not guess the password.";

pub fn print_try_hint() {
    println!();
    println!("See it in Cursor / Claude:");
    println!("  1. Write {TRY_FILE}:");
    print!("     {TRY_CONTENTS}");
    println!("  2. Ask the agent:");
    println!("     {TRY_PROMPT}");
    println!("  Expect {{{{PASSWORD:v1…}}}} — not the demo password.");
    println!("  Restore locally: offsend unseal");
}

pub fn print_post_install() {
    println!();
    println!("Offsend installed.");
    println!();
    println!("1. Check protection:");
    println!("   offsend doctor");
    println!();
    println!("2. See it in Cursor / Claude:");
    println!("   Write {TRY_FILE}:");
    print!("     {TRY_CONTENTS}");
    println!("   Ask the agent:");
    println!("     {TRY_PROMPT}");
    println!("   Expect {{{{PASSWORD:v1…}}}} — not the demo password.");
    println!("   Restore locally: offsend unseal");
}
