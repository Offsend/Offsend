fn main() {
    let version = std::env::var("OFFSEND_CLI_VERSION").unwrap_or_else(|_| {
        std::env::var("CARGO_PKG_VERSION").expect("CARGO_PKG_VERSION set by cargo")
    });
    println!("cargo:rustc-env=OFFSEND_CLI_VERSION={version}");
    println!("cargo:rerun-if-env-changed=OFFSEND_CLI_VERSION");
}
