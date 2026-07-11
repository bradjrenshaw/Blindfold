use std::cell::RefCell;
use std::path::PathBuf;
use std::rc::Rc;

use wxdragon::prelude::*;

use crate::core::{detect, github, install, uninstall};

struct State {
    release: Option<github::ReleaseInfo>,
    all_releases: Vec<github::ReleaseInfo>,
}

pub fn run() {
    wxdragon::main(|_app| {
        let frame = Frame::builder()
            .with_title("Blindfold Installer")
            .with_size(Size::new(650, 500))
            .build();

        let panel = Panel::builder(&frame).build();
        let main_sizer = BoxSizer::builder(Orientation::Vertical).build();

        // Status text
        let status = StaticText::builder(&panel)
            .with_label("Detecting game directory...")
            .build();

        // Game path row
        let path_sizer = BoxSizer::builder(Orientation::Horizontal).build();
        let path_label = StaticText::builder(&panel)
            .with_label("Game directory:")
            .build();
        let path_input = TextCtrl::builder(&panel).build();
        let browse_btn = Button::builder(&panel)
            .with_label("Browse...")
            .build();

        path_sizer.add(&path_label, 0, SizerFlag::All, 4);
        path_sizer.add(&path_input, 1, SizerFlag::Expand | SizerFlag::All, 4);
        path_sizer.add(&browse_btn, 0, SizerFlag::All, 4);

        // Log area
        let log = TextCtrl::builder(&panel)
            .with_style(TextCtrlStyle::MultiLine | TextCtrlStyle::ReadOnly | TextCtrlStyle::WordWrap)
            .build();

        // Button row
        let btn_sizer = BoxSizer::builder(Orientation::Horizontal).build();
        let install_btn = Button::builder(&panel)
            .with_label("Install")
            .build();
        let install_file_btn = Button::builder(&panel)
            .with_label("Install from file...")
            .build();
        let uninstall_btn = Button::builder(&panel)
            .with_label("Uninstall")
            .build();

        btn_sizer.add_stretch_spacer(1);
        btn_sizer.add(&install_btn, 0, SizerFlag::All, 4);
        btn_sizer.add(&install_file_btn, 0, SizerFlag::All, 4);
        btn_sizer.add(&uninstall_btn, 0, SizerFlag::All, 4);

        // Layout
        main_sizer.add(&status, 0, SizerFlag::Expand | SizerFlag::All, 8);
        main_sizer.add_sizer(&path_sizer, 0, SizerFlag::Expand | SizerFlag::Left | SizerFlag::Right, 8);
        main_sizer.add(&log, 1, SizerFlag::Expand | SizerFlag::All, 8);
        main_sizer.add_sizer(&btn_sizer, 0, SizerFlag::Expand | SizerFlag::All, 4);

        panel.set_sizer(main_sizer, true);

        // Disable action buttons initially
        install_btn.enable(false);
        install_file_btn.enable(false);
        uninstall_btn.enable(false);

        // Shared state
        let state = Rc::new(RefCell::new(State { release: None, all_releases: Vec::new() }));

        // Auto-detect game path
        if let Some(detected) = detect::detect_game_path() {
            path_input.set_value(&detected.to_string_lossy());
            log_append(&log, &format!("Game directory: {}", detected.display()));
            update_state(
                &status, &install_btn, &install_file_btn, &uninstall_btn,
                &detected, &state, &log,
            );
        } else {
            status.set_label("Game directory not found. Please browse to select it.");
            log_append(&log, "Could not auto-detect the Balatro game directory.");
        }

        // Fetch release info (before showing window, so no visible delay)
        match github::fetch_all_releases() {
            Ok(releases) => {
                // First non-prerelease is the "latest"
                let latest = releases.iter().find(|r| !r.prerelease).cloned();
                if let Some(ref info) = latest {
                    log_append(&log, &format!("Latest version: {}", info.tag_name));
                }
                {
                    let mut s = state.borrow_mut();
                    s.all_releases = releases;
                    s.release = latest;
                }
                let path = PathBuf::from(path_input.get_value());
                if detect::validate_game_path(&path) {
                    update_state(
                        &status, &install_btn, &install_file_btn, &uninstall_btn,
                        &path, &state, &log,
                    );
                }
            }
            Err(e) => {
                log_append(&log, &format!("Failed to check for updates: {}", e));
                status.set_label("Could not connect to GitHub. Install/update unavailable.");
            }
        }

        // Browse button
        {
            let frame_c = frame.clone();
            let path_input_c = path_input.clone();
            let status_c = status.clone();
            let install_btn_c = install_btn.clone();
            let install_file_btn_c = install_file_btn.clone();
            let uninstall_btn_c = uninstall_btn.clone();
            let log_c = log.clone();
            let state_c = state.clone();

            browse_btn.on_click(move |_| {
                let dialog = DirDialog::builder(&frame_c, "Select the Balatro game directory", "")
                    .build();
                if dialog.show_modal() == ID_OK {
                    if let Some(path_str) = dialog.get_path() {
                        let path = PathBuf::from(&path_str);
                        if !detect::validate_game_path(&path) {
                            log_append(&log_c, &format!("No Balatro.exe in: {}", path.display()));
                            status_c.set_label("Invalid game directory. Please browse to select it.");
                            return;
                        }
                        path_input_c.set_value(&path.to_string_lossy());
                        log_append(&log_c, &format!("Game directory: {}", path.display()));
                        update_state(
                            &status_c, &install_btn_c, &install_file_btn_c,
                            &uninstall_btn_c, &path, &state_c, &log_c,
                        );
                    }
                }
            });
        }

        // Install button
        {
            let frame_c = frame.clone();
            let path_input_c = path_input.clone();
            let status_c = status.clone();
            let install_btn_c = install_btn.clone();
            let install_file_btn_c = install_file_btn.clone();
            let uninstall_btn_c = uninstall_btn.clone();
            let browse_btn_c = browse_btn.clone();
            let log_c = log.clone();
            let state_c = state.clone();

            install_btn.on_click(move |_| {
                let game_path = PathBuf::from(path_input_c.get_value());
                let borrow = state_c.borrow();
                if borrow.all_releases.is_empty() { return; }

                // Build version list for picker
                let choices: Vec<String> = borrow.all_releases.iter().map(|r| {
                    if r.prerelease {
                        format!("{} (pre-release)", r.tag_name)
                    } else {
                        r.tag_name.clone()
                    }
                }).collect();
                let choice_refs: Vec<&str> = choices.iter().map(|s| s.as_str()).collect();

                drop(borrow);

                let dialog = SingleChoiceDialog::builder(
                    &frame_c,
                    "Select a version to install:",
                    "Choose Version",
                    &choice_refs,
                )
                .build();

                if dialog.show_modal() != ID_OK {
                    return;
                }
                let selection = dialog.get_selection();
                if selection < 0 { return; }

                let borrow = state_c.borrow();
                let info = &borrow.all_releases[selection as usize];

                if !info.body.is_empty() {
                    let dialog = MessageDialog::builder(
                        &frame_c,
                        &format!("Release notes for {}:\n\n{}\n\nProceed?", info.tag_name, info.body),
                        &format!("Install {}", info.tag_name),
                    )
                    .with_style(MessageDialogStyle::YesNo | MessageDialogStyle::IconQuestion)
                    .build();
                    if dialog.show_modal() != ID_YES {
                        return;
                    }
                }

                let Some(asset) = github::find_zip_asset(&info.assets) else {
                    log_append(&log_c, "Error: No .zip asset found in the release.");
                    return;
                };

                let url = asset.browser_download_url.clone();
                let version = info.tag_name.clone();
                drop(borrow);

                // Disable buttons during download
                install_btn_c.enable(false);
                install_file_btn_c.enable(false);
                uninstall_btn_c.enable(false);
                browse_btn_c.enable(false);
                log_append(&log_c, "Downloading...");
                status_c.set_label("Downloading...");

                let result = install::download_and_extract(&url, &game_path, |_pct| {});

                install_btn_c.enable(true);
                install_file_btn_c.enable(true);
                uninstall_btn_c.enable(true);
                browse_btn_c.enable(true);

                match result {
                    Ok(_) => {
                        if let Err(e) = install::save_installed_version(&version) {
                            log_append(&log_c, &format!("Warning: {}", e));
                        }
                        log_append(
                            &log_c,
                            &format!("Successfully installed version {}.", version),
                        );
                        update_state(
                            &status_c, &install_btn_c, &install_file_btn_c,
                            &uninstall_btn_c, &game_path, &state_c, &log_c,
                        );

                        MessageDialog::builder(
                            &frame_c,
                            &format!(
                                "Blindfold version {} installed successfully!\n\n\
                                 Launch Balatro through Steam — you should hear \"Blindfold loaded.\"",
                                version
                            ),
                            "Installation Complete",
                        )
                        .with_style(MessageDialogStyle::OK | MessageDialogStyle::IconInformation)
                        .build()
                        .show_modal();
                    }
                    Err(e) => {
                        log_append(&log_c, &format!("Error: {}", e));
                        MessageDialog::builder(&frame_c, &e, "Installation Failed")
                            .with_style(MessageDialogStyle::OK | MessageDialogStyle::IconError)
                            .build()
                            .show_modal();
                    }
                }
            });
        }

        // Install from file button
        {
            let frame_c = frame.clone();
            let path_input_c = path_input.clone();
            let status_c = status.clone();
            let install_btn_c = install_btn.clone();
            let install_file_btn_c = install_file_btn.clone();
            let uninstall_btn_c = uninstall_btn.clone();
            let log_c = log.clone();
            let state_c = state.clone();

            install_file_btn.on_click(move |_| {
                let game_path = PathBuf::from(path_input_c.get_value());

                let dialog = FileDialog::builder(&frame_c)
                    .with_message("Select the Blindfold zip file")
                    .with_wildcard("Zip files (*.zip)|*.zip")
                    .with_style(FileDialogStyle::Open | FileDialogStyle::FileMustExist)
                    .build();

                if dialog.show_modal() != ID_OK {
                    return;
                }
                let Some(zip_path_str) = dialog.get_path() else { return };
                let zip_path = PathBuf::from(&zip_path_str);

                match install::install_from_file(&zip_path, &game_path) {
                    Ok(_) => {
                        log_append(
                            &log_c,
                            &format!(
                                "Installed from {}.",
                                zip_path.file_name().unwrap_or_default().to_string_lossy()
                            ),
                        );
                        update_state(
                            &status_c, &install_btn_c, &install_file_btn_c,
                            &uninstall_btn_c, &game_path, &state_c, &log_c,
                        );

                        MessageDialog::builder(
                            &frame_c,
                            "Blindfold installed successfully from file!",
                            "Installation Complete",
                        )
                        .with_style(MessageDialogStyle::OK | MessageDialogStyle::IconInformation)
                        .build()
                        .show_modal();
                    }
                    Err(e) => {
                        log_append(&log_c, &format!("Error: {}", e));
                        MessageDialog::builder(&frame_c, &e, "Error")
                            .with_style(MessageDialogStyle::OK | MessageDialogStyle::IconError)
                            .build()
                            .show_modal();
                    }
                }
            });
        }

        // Uninstall button
        {
            let frame_c = frame.clone();
            let path_input_c = path_input.clone();
            let status_c = status.clone();
            let install_btn_c = install_btn.clone();
            let install_file_btn_c = install_file_btn.clone();
            let uninstall_btn_c = uninstall_btn.clone();
            let log_c = log.clone();
            let state_c = state.clone();

            uninstall_btn.on_click(move |_| {
                let game_path = PathBuf::from(path_input_c.get_value());

                let confirm_msg = if detect::is_dev_link() {
                    "Remove the Blindfold mod?\n\n\
                     Mods\\Blindfold is a link into a development checkout: only the \
                     link is removed, the checkout itself is left alone."
                } else {
                    "Remove the Blindfold mod?"
                };
                let dialog = MessageDialog::builder(
                    &frame_c,
                    confirm_msg,
                    "Confirm Uninstall",
                )
                .with_style(MessageDialogStyle::YesNo | MessageDialogStyle::IconQuestion)
                .build();

                if dialog.show_modal() != ID_YES {
                    return;
                }

                match uninstall::uninstall_mod() {
                    Ok(uninstall::UninstallOutcome::RemovedFolder) => {
                        log_append(&log_c, "Removed the mod folder.")
                    }
                    Ok(uninstall::UninstallOutcome::RemovedLink) => log_append(
                        &log_c,
                        "Removed the developer link; the checkout it pointed at is untouched.",
                    ),
                    Ok(uninstall::UninstallOutcome::NotInstalled) => {
                        log_append(&log_c, "Mod folder not found; nothing to remove.")
                    }
                    Err(e) => {
                        log_append(&log_c, &format!("Error: {}", e));
                        MessageDialog::builder(&frame_c, &e, "Uninstall Failed")
                            .with_style(MessageDialogStyle::OK | MessageDialogStyle::IconError)
                            .build()
                            .show_modal();
                        return;
                    }
                }

                if uninstall::other_mods_present() {
                    log_append(
                        &log_c,
                        "Other mods are still in your Mods folder; leaving the Lovely Injector in place.",
                    );
                } else {
                    let remove_lovely = MessageDialog::builder(
                        &frame_c,
                        "Also remove the Lovely Injector (version.dll) from the game folder?\n\n\
                         It's only needed for mods; removing it returns the game to fully vanilla.",
                        "Remove Lovely Injector",
                    )
                    .with_style(MessageDialogStyle::YesNo | MessageDialogStyle::IconQuestion)
                    .build()
                    .show_modal();

                    if remove_lovely == ID_YES {
                        match uninstall::remove_lovely(&game_path) {
                            Ok(true) => log_append(&log_c, "Removed version.dll."),
                            Ok(false) => log_append(&log_c, "version.dll was not present."),
                            Err(e) => log_append(&log_c, &format!("Error: {}", e)),
                        }
                    }
                }

                let remove_settings = MessageDialog::builder(
                    &frame_c,
                    "Also remove Blindfold's settings, keybinds, and speech log?\n\n\
                     Game saves are never touched.",
                    "Remove Settings",
                )
                .with_style(MessageDialogStyle::YesNo | MessageDialogStyle::IconQuestion)
                .build()
                .show_modal();

                if remove_settings == ID_YES {
                    let removed = uninstall::remove_user_files();
                    if removed.is_empty() {
                        log_append(&log_c, "No settings files found.");
                    } else {
                        log_append(&log_c, &format!("Removed: {}", removed.join(", ")));
                    }
                }

                log_append(&log_c, "Uninstall complete.");
                update_state(
                    &status_c, &install_btn_c, &install_file_btn_c,
                    &uninstall_btn_c, &game_path, &state_c, &log_c,
                );

                MessageDialog::builder(
                    &frame_c,
                    "Blindfold has been uninstalled.",
                    "Uninstall Complete",
                )
                .with_style(MessageDialogStyle::OK | MessageDialogStyle::IconInformation)
                .build()
                .show_modal();
            });
        }

        frame.show(true);
    })
    .expect("Failed to start application");
}

fn update_state(
    status: &StaticText,
    install_btn: &Button,
    install_file_btn: &Button,
    uninstall_btn: &Button,
    game_path: &std::path::Path,
    state: &Rc<RefCell<State>>,
    log: &TextCtrl,
) {
    let dev_link = detect::is_dev_link();
    let mod_installed = detect::is_mod_installed();
    let installed_version = install::get_installed_version();
    let has_valid_path = detect::validate_game_path(game_path);

    if dev_link {
        install_btn.enable(false);
        install_file_btn.enable(false);
        uninstall_btn.enable(true);
        status.set_label("Developer install detected — update with 'git pull'.");
        log_append(
            log,
            "Mods\\Blindfold is a link into a development checkout (scripts\\deploy.ps1). \
             Update with 'git pull', or Uninstall to remove the link (the checkout \
             itself is left alone) and install a release instead.",
        );
        return;
    }

    install_file_btn.enable(has_valid_path);
    uninstall_btn.enable(mod_installed);

    if mod_installed {
        log_append(
            log,
            &format!(
                "Installed version: {}",
                installed_version.as_deref().unwrap_or("unknown")
            ),
        );
    }

    let borrow = state.borrow();
    if let Some(info) = borrow.release.as_ref() {
        let latest = &info.tag_name;
        if !has_valid_path {
            install_btn.enable(false);
        } else if !mod_installed {
            install_btn.set_label("Install");
            install_btn.enable(true);
            status.set_label(&format!("Ready to install version {}.", latest));
        } else if is_up_to_date(installed_version.as_deref(), latest) {
            install_btn.set_label("Install");
            install_btn.enable(false);
            status.set_label(&format!("Blindfold is up to date (version {}).", latest));
        } else {
            install_btn.set_label("Update");
            install_btn.enable(true);
            status.set_label(&format!(
                "Update available: {} → {}",
                installed_version.as_deref().unwrap_or("unknown"),
                latest
            ));
        }
    }
}

fn parse_version(s: &str) -> Option<semver::Version> {
    let trimmed = s.strip_prefix('v').or_else(|| s.strip_prefix('V')).unwrap_or(s);
    semver::Version::parse(trimmed).ok()
}

/// Returns true if the installed version is >= the latest version.
fn is_up_to_date(installed: Option<&str>, latest: &str) -> bool {
    let Some(installed) = installed else { return false };
    match (parse_version(installed), parse_version(latest)) {
        (Some(inst), Some(lat)) => inst >= lat,
        _ => installed == latest, // fallback to string comparison
    }
}

fn log_append(log: &TextCtrl, msg: &str) {
    let current = log.get_value();
    if current.is_empty() {
        log.set_value(msg);
    } else {
        log.set_value(&format!("{}\n{}", current, msg));
    }
}
