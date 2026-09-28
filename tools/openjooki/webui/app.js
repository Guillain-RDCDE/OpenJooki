/* OpenJooki web UI — local management page for a Jooki v2.
   Talks to the Jooki only (MQTT over WebSocket on port 8000 + HTTP /upload).
   No tracker, no cloud, no external resource. */
(function () {
  'use strict';

  var CFG = window.OJ_CONFIG || {};
  var VERSION = '2.0.3';

  /* ------------------------------------------------------------------ i18n */
  var T = {
    fr: {
      playlists: 'Playlists', tokens: 'Jetons', library: 'Bibliothèque', settings: 'Réglages',
      connecting: 'Connexion au Jooki…', connected: 'Connecté', offline: 'Hors ligne',
      offline_long: 'Le Jooki ne répond pas. Vérifie qu\'il est allumé et sur le même Wi-Fi. Nouvelle tentative automatique…',
      retry: 'Réessayer',
      new_playlist: 'Nouvelle playlist', create: 'Créer', cancel: 'Annuler', save: 'Enregistrer', close: 'Fermer',
      name: 'Nom', playlist_name_ph: 'Ex. : Comptines du soir',
      n_tracks: function (n) { return n + (n > 1 ? ' pistes' : ' piste'); },
      audiobook: 'Livre audio', audiobook_help: 'Reprend toujours là où on s\'était arrêté, sans lecture aléatoire.',
      no_token: 'Aucun jeton', choose_token: 'Choisir le personnage', token_for: 'Personnage qui lance cette playlist',
      token_help: 'Tous les jetons d\'un même personnage lancent cette playlist (par exemple tous les dragons noirs).',
      used_by: function (t) { return 'déjà sur « ' + t + ' »'; },
      token_moved: function (t) { return 'Ce personnage lançait « ' + t + ' ». Il lancera désormais cette playlist.'; },
      play: 'Lire', pause: 'Pause', next: 'Suivant', prev: 'Précédent',
      add_files: 'Ajouter des fichiers', from_library: 'Depuis la bibliothèque', web_radio: 'Radio web',
      delete_playlist: 'Supprimer la playlist',
      delete_playlist_q: function (t) { return 'Supprimer « ' + t + ' » ?'; },
      delete_playlist_text: 'La playlist est supprimée. Ses morceaux restent sur le Jooki (dans « Non utilisées »).',
      delete: 'Supprimer', rename: 'Renommer',
      empty_playlist: 'Cette playlist est vide.', empty_playlist_hint: 'Ajoute des fichiers depuis ton téléphone ou ton ordinateur, ou des morceaux déjà présents sur le Jooki.',
      drop_here: 'Glisse des fichiers audio ici', removed_from: 'Retiré de la playlist', undo: 'Annuler',
      playlist_missing: 'Cette playlist n\'existe plus.', back: 'Retour',
      no_playlists: 'Aucune playlist pour l\'instant.',
      unused_banner: function (n) { return n + (n > 1 ? ' morceaux ne sont' : ' morceau n\'est') + ' dans aucune playlist.'; },
      see: 'Voir',
      all: 'Tous', unused: 'Non utilisés', search: 'Rechercher', in_playlists: 'Dans : ', in_none: 'Dans aucune playlist',
      add_to: 'Ajouter à…', selected: function (n) { return n + (n > 1 ? ' sélectionnés' : ' sélectionné'); },
      select_all: 'Tout sélectionner', select_none: 'Tout désélectionner',
      delete_forever: 'Supprimer du Jooki',
      delete_forever_q: function (n) { return 'Supprimer définitivement ' + n + (n > 1 ? ' morceaux' : ' morceau') + ' ?'; },
      delete_forever_text: 'Les fichiers seront effacés du Jooki. Cette action est irréversible.',
      deleted: 'Supprimé', choose_playlist: 'Choisir une playlist', added: function (n) { return n + (n > 1 ? ' morceaux ajoutés' : ' morceau ajouté'); },
      already_in: 'déjà dedans', add: 'Ajouter', add_n: function (n) { return 'Ajouter ' + n; },
      library_empty: 'Aucun morceau sur le Jooki.', unused_empty: 'Tous les morceaux sont dans une playlist.',
      radio: 'Radio', radio_title: 'Ajouter une radio web', radio_name: 'Nom de la radio', radio_url: 'Adresse du flux (http:// ou https://)',
      radio_url_bad: 'L\'adresse doit commencer par http:// ou https://',
      tokens_intro: 'Chaque personnage lance une playlist. Tous les jetons d\'un même personnage (par exemple tous tes dragons noirs) font exactement la même chose.',
      tokens_hint: 'Pose un jeton sur le Jooki pour le faire apparaître ici.',
      nfc_tag: 'Tag NFC', foreign_hint: 'Un autre objet NFC (un amiibo, un autocollant) apparaît aussi ici quand tu le poses : il lance sa playlist, mais le retirer ne met pas en pause, et il faut poser autre chose entre deux poses. Utilise le bouton pour la pause.',
      launches: 'Lance', none_dash: '— Aucune playlist —',
      token_n: function (n) { return 'Jeton ' + n; }, token_name_ph: 'Surnom (facultatif)', tag_name_ph: 'Nom de ce tag (pour t\'y retrouver)',
      tok_search_ph: 'Rechercher un jeton par son nom', tok_no_match: 'Aucun jeton ne porte ce nom.',
      photo_btn: 'Photo', photo_remove: 'Retirer la photo', ed_title: 'La photo du tag',
      ed_hint: 'Touche une zone pour l\'enlever (baguette magique). Glisse pour déplacer.', ed_bg: 'Enlever le fond',
      ed_tol: 'Tolérance', ed_rot: 'Rotation', ed_zoom: 'Zoom', ed_undo: 'Annuler le dernier', ed_reset: 'Tout remettre', ed_save: 'Enregistrer',
      ed_sending: 'Envoi de la photo…', photo_fail: 'La photo n\'a pas pu être enregistrée.', photo_bad: 'Ce fichier n\'est pas une image lisible.',
      pl_taken: function (pl, ch) { return '« ' + pl + ' » est lancée par ' + ch + '. La donner à ce jeton à la place ?'; },
      seen_n: function (n) { return 'posé ' + n + ' fois'; }, on_jooki: 'Sur le Jooki',
      forget: 'Oublier', forget_q: 'Oublier ce jeton ?',
      forget_text: 'Il disparaît de la liste et réapparaîtra la prochaine fois qu\'il sera posé. La playlist du personnage ne change pas.',
      saved: 'Enregistré', no_tokens: 'Aucun jeton connu pour l\'instant.',
      other_chars: 'Personnages sans jeton connu',
      device: 'Appareil', device_name: 'Nom', battery: 'Batterie', charging: 'en charge', plugged: 'branché',
      rename: 'Renommer', name_title: 'Nom du Jooki sur le réseau',
      name_help: function (f) { return 'Lettres minuscules, chiffres et tirets. La page s\'ouvrira à l\'adresse nom.local. Laisse vide pour revenir au nom d\'origine (' + f + ').'; },
      name_invalid: 'Lettres minuscules, chiffres et tirets seulement (32 au plus), sans tiret au début ni à la fin.',
      name_done: function (n) { return 'Le Jooki s\'appelle maintenant ' + n; },
      name_text: function (u) { return 'Sa page est désormais à l\'adresse ' + u + ' — l\'ancienne ne répond plus. Garde ce lien en favori. Spotify affichera le nouveau nom au prochain redémarrage.'; },
      name_open: 'Ouvrir la nouvelle adresse',
      wifi: 'Wi-Fi', ip: 'Adresse IP', storage: 'Stockage', free: 'libres', version: 'Version',
      playback: 'Lecture', toy_safe: 'Volume limité (mode enfant)', shuffle: 'Aléatoire', repeat: 'Répéter',
      language: 'Langue', power_off: 'Éteindre le Jooki', power_off_q: 'Éteindre le Jooki ?',
      power_off_text: 'Il faudra appuyer sur son bouton pour le rallumer.', power_off_done: 'Le Jooki s\'éteint…',
      nothing_playing: 'Rien en lecture', nothing_hint: 'Pose un jeton ou choisis une playlist',
      live: 'En direct', volume: 'Volume',
      uploading: 'Envoi', processing: 'Analyse sur le Jooki…', done: 'Ajouté', queued: 'En attente',
      up_too_small: 'Fichier vide ou trop petit', up_no_space: 'Plus assez de place sur le Jooki',
      up_net: 'Échec de l\'envoi (connexion perdue ?)', up_type: 'Ce fichier n\'est pas un format audio reconnu',
      up_fail: 'Le Jooki n\'a pas pu ajouter ce fichier', up_timeout: 'Pas de réponse du Jooki',
      uploads_running: 'Des envois sont en cours. Quitter la page les interrompra.',
      clear_done: 'Masquer les envois terminés',
      up_retrying: function (n, m) { return 'Connexion perdue, nouvel essai (' + n + '/' + m + ')…'; }, up_retry: 'Réessayer',
      wifi_good: 'Signal bon', wifi_fair: 'Signal moyen', wifi_weak: 'Signal faible',
      wifi_drops: function (n) { return n + (n > 1 ? ' coupures' : ' coupure') + ' depuis le démarrage'; },
      wifi_advice: 'Rapprochez le Jooki d\'une borne Wi-Fi. La musique marche sans Wi-Fi : seuls cette page et les envois en ont besoin.',
      err_readonly: 'Action impossible sur les morceaux non utilisés.',
      err_internal: 'Le Jooki a rencontré une erreur. Réessaie.',
      err_empty_title: 'Le nom ne peut pas être vide.',
      err_radio: 'Adresse de radio invalide.',
      err_gone: 'Cet élément n\'existe plus.',
      err_generic: 'Le Jooki a refusé l\'action.',
      err_unknown_char: 'Personnage inconnu.',
      duration_total: function (s) { return s; },
      mute_unsupported: '',
      files_hint: 'MP3, M4A, OGG, FLAC, WAV…',
      open_player: 'Ouvrir le lecteur',
      web_page: 'page', upd_check: 'Rechercher une mise à jour', upd_checking: 'Recherche…',
      upd_uptodate: 'Ton Jooki est à jour.', upd_offline: 'Impossible de joindre GitHub (le Jooki a-t-il Internet ?).',
      upd_available: function (v) { return 'Nouvelle version ' + v + ' disponible'; }, upd_now: 'Mettre à jour maintenant',
      upd_q: function (v) { return 'Mettre à jour vers OpenJooki ' + v + ' ?'; },
      upd_text: 'Le Jooki télécharge la nouvelle version et redémarre tout seul : jusqu\'à 10 minutes. Garde-le branché. Ta musique et tes jetons sont conservés, et il revient tout seul à l\'ancienne version si quelque chose se passe mal.',
      upd_running: 'Mise à jour en cours…', upd_keep: 'Garde le Jooki branché. Cette page se reconnecte toute seule.',
      upd_rebooting: 'Le Jooki redémarre sur la nouvelle version…', upd_done: function (v) { return 'Jooki mis à jour : OpenJooki ' + v; },
      upd_failed: 'La mise à jour n\'a pas pu se faire. Ton Jooki n\'a pas changé.', upd_banner: function (v) { return 'Mise à jour ' + v + ' disponible'; },
      upd_see: 'Voir',
      upd_steps: ['Recherche de la nouvelle version', 'Téléchargement', 'Vérification du téléchargement', 'Installation (ne débranche pas le Jooki)', 'Vérification de l\'installation', 'Redémarrage sur la nouvelle version'],
      bedtime: 'Heure du coucher', sleep_timer: 'Minuterie', sleep_off: 'Arrêt',
      sleep_min: function (n) { return n + ' min'; }, sleep_track: 'Fin du chapitre',
      sleep_left: function (s) { return 'Arrêt dans ' + s; }, sleep_at_end: 'Arrêt à la fin de ce morceau',
      sleep_auto: 'automatique (mode nuit)', sleep_cancel: 'Annuler la minuterie',
      night_mode: 'Mode nuit', night_help: 'Pendant ces heures, chaque écoute s\'arrête toute seule, le volume est limité et les lumières sont tamisées.',
      night_from: 'De', night_to: 'À', night_timer: 'Minuterie automatique', night_timer_none: 'Aucune',
      night_maxvol: 'Volume maximum', night_nolimit: 'pas de limite', night_dim: 'Lumières tamisées',
      night_now: 'Mode nuit en ce moment', night_next: function (h) { return 'Commence à ' + h; },
      night_clock: 'L\'heure du Jooki vient d\'Internet (heure d\'été comprise).',
      resume_at: function (c, s) { return 'Reprendra au chapitre ' + c + (s ? ' · ' + s : ''); },
      resume_restart: 'Recommencer au début', resume_done: 'Reprendra au chapitre 1',
      sort: 'Trier', sort_title: 'Ranger la playlist', sorted: 'Pistes remises dans l\'ordre',
      sort_by_name: 'Nom de fichier (1, 2, 3…)', sort_by_title: 'Titre', sort_by_artist: 'Artiste', sort_by_album: 'Album', sort_by_duration: 'Durée',
      sort_again: 'Un second appui sur le même critère inverse l\'ordre.', sort_preview: 'Aperçu du nouvel ordre',
      sort_apply: 'Fixer cet ordre', sort_same: 'La playlist est déjà dans cet ordre',
      my_jooki: 'Mon Jooki', bytes: ['o', 'Ko', 'Mo', 'Go'],
      n_tokens: function (n) { return n + ' jeton' + (n > 1 ? 's' : ''); },
      sec_title: 'Sécurité',
      ssh_label: 'Accès de maintenance (SSH)', ssh_help: 'Pour les bricoleurs. S\'éteint tout seul au bout d\'une heure.', ssh_on: 'activé (1 h)',
      mqtt_label: 'Domotique (MQTT sur le réseau)', mqtt_help: 'Pour Home Assistant. Désactivée par défaut.',
      mqtt_host_l: 'Hôte', mqtt_port_l: 'Port', mqtt_user_l: 'Utilisateur', mqtt_pass_l: 'Mot de passe',
      parent_label: 'Code parent', parent_help: 'Un code à 4 chiffres empêche enfants et invités de changer les réglages (supprimer une playlist, le Wi-Fi, lancer une mise à jour).',
      parent_set: 'Définir un code', parent_change: 'Changer le code', parent_off: 'Désactiver',
      parent_prompt: 'Entre le code parent', parent_new: 'Code à 4 chiffres', parent_cur: 'Code actuel', parent_bad: 'Code incorrect',
      parent_reset: 'Code oublié ? Appuie 10 secondes sur ◀ et ▶ ensemble sur le Jooki.'
    },
    en: {
      playlists: 'Playlists', tokens: 'Tokens', library: 'Library', settings: 'Settings',
      connecting: 'Connecting to the Jooki…', connected: 'Connected', offline: 'Offline',
      offline_long: 'The Jooki is not answering. Check it is on and on the same Wi-Fi. Retrying automatically…',
      retry: 'Retry',
      new_playlist: 'New playlist', create: 'Create', cancel: 'Cancel', save: 'Save', close: 'Close',
      name: 'Name', playlist_name_ph: 'E.g. Bedtime songs',
      n_tracks: function (n) { return n + (n === 1 ? ' track' : ' tracks'); },
      audiobook: 'Audiobook', audiobook_help: 'Always resumes where it stopped, never shuffled.',
      no_token: 'No token', choose_token: 'Choose the character', token_for: 'Character that starts this playlist',
      token_help: 'Every token of the same character starts this playlist (e.g. all black dragons).',
      used_by: function (t) { return 'on “' + t + '”'; },
      token_moved: function (t) { return 'This character used to start “' + t + '”. It will now start this playlist.'; },
      play: 'Play', pause: 'Pause', next: 'Next', prev: 'Previous',
      add_files: 'Add files', from_library: 'From the library', web_radio: 'Web radio',
      delete_playlist: 'Delete playlist',
      delete_playlist_q: function (t) { return 'Delete “' + t + '”?'; },
      delete_playlist_text: 'The playlist is deleted. Its tracks stay on the Jooki (under “Unused”).',
      delete: 'Delete', rename: 'Rename',
      empty_playlist: 'This playlist is empty.', empty_playlist_hint: 'Add files from your phone or computer, or tracks already on the Jooki.',
      drop_here: 'Drop audio files here', removed_from: 'Removed from the playlist', undo: 'Undo',
      playlist_missing: 'This playlist no longer exists.', back: 'Back',
      no_playlists: 'No playlist yet.',
      unused_banner: function (n) { return n + (n === 1 ? ' track is' : ' tracks are') + ' in no playlist.'; },
      see: 'Show',
      all: 'All', unused: 'Unused', search: 'Search', in_playlists: 'In: ', in_none: 'In no playlist',
      add_to: 'Add to…', selected: function (n) { return n + ' selected'; },
      select_all: 'Select all', select_none: 'Deselect all',
      delete_forever: 'Delete from Jooki',
      delete_forever_q: function (n) { return 'Permanently delete ' + n + (n === 1 ? ' track' : ' tracks') + '?'; },
      delete_forever_text: 'The files will be erased from the Jooki. This cannot be undone.',
      deleted: 'Deleted', choose_playlist: 'Choose a playlist', added: function (n) { return n + (n === 1 ? ' track added' : ' tracks added'); },
      already_in: 'already in', add: 'Add', add_n: function (n) { return 'Add ' + n; },
      library_empty: 'No track on the Jooki.', unused_empty: 'Every track is in a playlist.',
      radio: 'Radio', radio_title: 'Add a web radio', radio_name: 'Radio name', radio_url: 'Stream address (http:// or https://)',
      radio_url_bad: 'The address must start with http:// or https://',
      tokens_intro: 'Each character starts one playlist. All tokens of the same character (e.g. all your black dragons) do exactly the same thing.',
      tokens_hint: 'Put a token on the Jooki to see it here.',
      nfc_tag: 'NFC tag', foreign_hint: 'Another NFC object (an amiibo, a sticker) also shows up here when you put it on: it starts its playlist, but taking it off does not pause, and something else has to be put on between two taps. Use the button to pause.',
      launches: 'Starts', none_dash: '— No playlist —',
      token_n: function (n) { return 'Token ' + n; }, token_name_ph: 'Nickname (optional)', tag_name_ph: 'Name this tag (to tell them apart)',
      tok_search_ph: 'Search a token by name', tok_no_match: 'No token has that name.',
      photo_btn: 'Photo', photo_remove: 'Remove the photo', ed_title: 'The tag\'s photo',
      ed_hint: 'Tap a zone to remove it (magic wand). Drag to move.', ed_bg: 'Remove the background',
      ed_tol: 'Tolerance', ed_rot: 'Rotation', ed_zoom: 'Zoom', ed_undo: 'Undo last', ed_reset: 'Start over', ed_save: 'Save',
      ed_sending: 'Sending the photo…', photo_fail: 'The photo could not be saved.', photo_bad: 'This file is not a readable image.',
      pl_taken: function (pl, ch) { return '“' + pl + '” is started by ' + ch + '. Give it to this token instead?'; },
      seen_n: function (n) { return 'used ' + n + (n === 1 ? ' time' : ' times'); }, on_jooki: 'On the Jooki',
      forget: 'Forget', forget_q: 'Forget this token?',
      forget_text: 'It leaves the list and comes back next time it is used. The character\'s playlist does not change.',
      saved: 'Saved', no_tokens: 'No known token yet.',
      other_chars: 'Characters without a known token',
      device: 'Device', device_name: 'Name', battery: 'Battery', charging: 'charging', plugged: 'plugged in',
      rename: 'Rename', name_title: 'Jooki name on the network',
      name_help: function (f) { return 'Lower-case letters, digits and hyphens. The page will open at name.local. Leave empty to go back to the original name (' + f + ').'; },
      name_invalid: 'Lower-case letters, digits and hyphens only (32 at most), no hyphen at the start or the end.',
      name_done: function (n) { return 'The Jooki is now called ' + n; },
      name_text: function (u) { return 'Its page is now at ' + u + ' — the old address no longer answers. Bookmark this link. Spotify will show the new name after the next restart.'; },
      name_open: 'Open the new address',
      wifi: 'Wi-Fi', ip: 'IP address', storage: 'Storage', free: 'free', version: 'Version',
      playback: 'Playback', toy_safe: 'Limited volume (kids mode)', shuffle: 'Shuffle', repeat: 'Repeat',
      language: 'Language', power_off: 'Turn off the Jooki', power_off_q: 'Turn off the Jooki?',
      power_off_text: 'You will need to press its button to turn it back on.', power_off_done: 'The Jooki is turning off…',
      nothing_playing: 'Nothing playing', nothing_hint: 'Put a token or pick a playlist',
      live: 'Live', volume: 'Volume',
      uploading: 'Uploading', processing: 'Processing on the Jooki…', done: 'Added', queued: 'Waiting',
      up_too_small: 'Empty or too small file', up_no_space: 'Not enough space left on the Jooki',
      up_net: 'Upload failed (connection lost?)', up_type: 'This file is not a supported audio format',
      up_fail: 'The Jooki could not add this file', up_timeout: 'No answer from the Jooki',
      uploads_running: 'Uploads are in progress. Leaving the page will stop them.',
      clear_done: 'Hide finished uploads',
      up_retrying: function (n, m) { return 'Connection lost, retrying (' + n + '/' + m + ')…'; }, up_retry: 'Retry',
      wifi_good: 'Good signal', wifi_fair: 'Fair signal', wifi_weak: 'Weak signal',
      wifi_drops: function (n) { return n + (n === 1 ? ' drop' : ' drops') + ' since start-up'; },
      wifi_advice: 'Move the Jooki closer to a Wi-Fi access point. Music works without Wi-Fi: only this page and uploads need it.',
      err_readonly: 'Not possible on unused tracks.',
      err_internal: 'The Jooki hit an error. Please retry.',
      err_empty_title: 'The name cannot be empty.',
      err_radio: 'Invalid radio address.',
      err_gone: 'This item no longer exists.',
      err_generic: 'The Jooki refused the action.',
      err_unknown_char: 'Unknown character.',
      duration_total: function (s) { return s; },
      mute_unsupported: '',
      files_hint: 'MP3, M4A, OGG, FLAC, WAV…',
      open_player: 'Open the player',
      web_page: 'page', upd_check: 'Check for updates', upd_checking: 'Checking…',
      upd_uptodate: 'Your Jooki is up to date.', upd_offline: 'Cannot reach GitHub (is the Jooki online?).',
      upd_available: function (v) { return 'New version ' + v + ' available'; }, upd_now: 'Update now',
      upd_q: function (v) { return 'Update to OpenJooki ' + v + '?'; },
      upd_text: 'The Jooki downloads the new version and restarts on its own: up to 10 minutes. Keep it plugged in. Your music and tokens are kept, and it goes back to the previous version by itself if anything goes wrong.',
      upd_running: 'Updating…', upd_keep: 'Keep the Jooki plugged in. This page reconnects by itself.',
      upd_rebooting: 'The Jooki is restarting on the new version…', upd_done: function (v) { return 'Jooki updated: OpenJooki ' + v; },
      upd_failed: 'The update could not be done. Your Jooki has not changed.', upd_banner: function (v) { return 'Update ' + v + ' available'; },
      upd_see: 'Show',
      upd_steps: ['Looking for the new version', 'Downloading', 'Checking the download', 'Installing (keep the Jooki plugged in)', 'Checking the installation', 'Restarting on the new version'],
      bedtime: 'Bedtime', sleep_timer: 'Sleep timer', sleep_off: 'Off',
      sleep_min: function (n) { return n + ' min'; }, sleep_track: 'End of chapter',
      sleep_left: function (s) { return 'Stops in ' + s; }, sleep_at_end: 'Stops at the end of this track',
      sleep_auto: 'automatic (night mode)', sleep_cancel: 'Cancel the timer',
      night_mode: 'Night mode', night_help: 'During these hours, every listen stops by itself, the volume is limited and the lights are dimmed.',
      night_from: 'From', night_to: 'To', night_timer: 'Automatic timer', night_timer_none: 'None',
      night_maxvol: 'Maximum volume', night_nolimit: 'no limit', night_dim: 'Dimmed lights',
      night_now: 'Night mode right now', night_next: function (h) { return 'Starts at ' + h; },
      night_clock: 'The Jooki gets its time from the Internet (summer time included).',
      resume_at: function (c, s) { return 'Will resume at chapter ' + c + (s ? ' · ' + s : ''); },
      resume_restart: 'Start again from the beginning', resume_done: 'Will resume at chapter 1',
      sort: 'Sort', sort_title: 'Put the playlist in order', sorted: 'Tracks put back in order',
      sort_by_name: 'File name (1, 2, 3…)', sort_by_title: 'Title', sort_by_artist: 'Artist', sort_by_album: 'Album', sort_by_duration: 'Duration',
      sort_again: 'Tap the same criterion again to reverse the order.', sort_preview: 'Preview of the new order',
      sort_apply: 'Keep this order', sort_same: 'The playlist is already in this order',
      my_jooki: 'My Jooki', bytes: ['B', 'KB', 'MB', 'GB'],
      n_tokens: function (n) { return n + (n === 1 ? ' token' : ' tokens'); },
      sec_title: 'Security',
      ssh_label: 'Maintenance access (SSH)', ssh_help: 'For tinkerers. Turns itself off after an hour.', ssh_on: 'on (1 h)',
      mqtt_label: 'Home automation (MQTT on the network)', mqtt_help: 'For Home Assistant. Off by default.',
      mqtt_host_l: 'Host', mqtt_port_l: 'Port', mqtt_user_l: 'User', mqtt_pass_l: 'Password',
      parent_label: 'Parent code', parent_help: 'A 4-digit code stops children and guests from changing settings (deleting a playlist, Wi-Fi, starting an update).',
      parent_set: 'Set a code', parent_change: 'Change the code', parent_off: 'Turn off',
      parent_prompt: 'Enter the parent code', parent_new: '4-digit code', parent_cur: 'Current code', parent_bad: 'Wrong code',
      parent_reset: 'Forgot the code? Hold ◀ and ▶ together for 10 seconds on the Jooki.'
    },
    nl: {
      playlists: 'Afspeellijsten', tokens: 'Figuurtjes', library: 'Bibliotheek', settings: 'Instellingen',
      connecting: 'Verbinden met de Jooki…', connected: 'Verbonden', offline: 'Offline',
      offline_long: 'De Jooki antwoordt niet. Controleer of hij aanstaat en op dezelfde wifi zit. Er wordt automatisch opnieuw geprobeerd…',
      retry: 'Opnieuw proberen',
      new_playlist: 'Nieuwe afspeellijst', create: 'Aanmaken', cancel: 'Annuleren', save: 'Opslaan', close: 'Sluiten',
      name: 'Naam', playlist_name_ph: 'Bijv. Slaapliedjes',
      n_tracks: function (n) { return n + (n === 1 ? ' nummer' : ' nummers'); },
      audiobook: 'Luisterboek', audiobook_help: 'Gaat altijd verder waar het gestopt is, nooit in willekeurige volgorde.',
      no_token: 'Geen figuurtje', choose_token: 'Kies het personage', token_for: 'Personage dat deze afspeellijst start',
      token_help: 'Elk figuurtje van hetzelfde personage start deze afspeellijst (bijv. alle zwarte draken).',
      used_by: function (t) { return 'bij “' + t + '”'; },
      token_moved: function (t) { return 'Dit personage startte “' + t + '”. Voortaan start het deze afspeellijst.'; },
      play: 'Afspelen', pause: 'Pauze', next: 'Volgende', prev: 'Vorige',
      add_files: 'Bestanden toevoegen', from_library: 'Uit de bibliotheek', web_radio: 'Webradio',
      delete_playlist: 'Afspeellijst verwijderen',
      delete_playlist_q: function (t) { return '“' + t + '” verwijderen?'; },
      delete_playlist_text: 'De afspeellijst wordt verwijderd. De nummers blijven op de Jooki (onder “Ongebruikt”).',
      delete: 'Verwijderen', rename: 'Hernoemen',
      empty_playlist: 'Deze afspeellijst is leeg.', empty_playlist_hint: 'Voeg bestanden toe vanaf je telefoon of computer, of nummers die al op de Jooki staan.',
      drop_here: 'Sleep audiobestanden hierheen', removed_from: 'Uit de afspeellijst gehaald', undo: 'Ongedaan maken',
      playlist_missing: 'Deze afspeellijst bestaat niet meer.', back: 'Terug',
      no_playlists: 'Nog geen afspeellijst.',
      unused_banner: function (n) { return n + (n === 1 ? ' nummer staat' : ' nummers staan') + ' in geen enkele afspeellijst.'; },
      see: 'Bekijken',
      all: 'Alles', unused: 'Ongebruikt', search: 'Zoeken', in_playlists: 'In: ', in_none: 'In geen enkele afspeellijst',
      add_to: 'Toevoegen aan…', selected: function (n) { return n + ' geselecteerd'; },
      select_all: 'Alles selecteren', select_none: 'Selectie opheffen',
      delete_forever: 'Van de Jooki verwijderen',
      delete_forever_q: function (n) { return n + (n === 1 ? ' nummer' : ' nummers') + ' definitief verwijderen?'; },
      delete_forever_text: 'De bestanden worden van de Jooki gewist. Dit kan niet ongedaan worden gemaakt.',
      deleted: 'Verwijderd', choose_playlist: 'Kies een afspeellijst', added: function (n) { return n + (n === 1 ? ' nummer toegevoegd' : ' nummers toegevoegd'); },
      already_in: 'zit er al in', add: 'Toevoegen', add_n: function (n) { return n + ' toevoegen'; },
      library_empty: 'Geen nummers op de Jooki.', unused_empty: 'Elk nummer zit in een afspeellijst.',
      radio: 'Radio', radio_title: 'Een webradio toevoegen', radio_name: 'Naam van de radio', radio_url: 'Streamadres (http:// of https://)',
      radio_url_bad: 'Het adres moet beginnen met http:// of https://',
      tokens_intro: 'Elk personage start één afspeellijst. Alle figuurtjes van hetzelfde personage (bijv. al je zwarte draken) doen precies hetzelfde.',
      tokens_hint: 'Zet een figuurtje op de Jooki om het hier te zien.',
      nfc_tag: 'NFC-tag', foreign_hint: 'Een ander NFC-voorwerp (een amiibo, een sticker) verschijnt hier ook als je het erop zet: het start zijn afspeellijst, maar eraf halen pauzeert niet, en er moet iets anders op tussen twee keer. Gebruik de knop om te pauzeren.',
      launches: 'Start', none_dash: '— Geen afspeellijst —',
      token_n: function (n) { return 'Figuurtje ' + n; }, token_name_ph: 'Bijnaam (optioneel)', tag_name_ph: 'Naam van deze tag (om ze uit elkaar te houden)',
      tok_search_ph: 'Zoek een figuurtje op naam', tok_no_match: 'Geen figuurtje met die naam.',
      photo_btn: 'Foto', photo_remove: 'Foto verwijderen', ed_title: 'De foto van de tag',
      ed_hint: 'Tik op een zone om die weg te halen (toverstaf). Sleep om te verplaatsen.', ed_bg: 'Achtergrond weghalen',
      ed_tol: 'Tolerantie', ed_rot: 'Draaien', ed_zoom: 'Zoom', ed_undo: 'Laatste ongedaan maken', ed_reset: 'Opnieuw beginnen', ed_save: 'Opslaan',
      ed_sending: 'Foto wordt verstuurd…', photo_fail: 'De foto kon niet worden opgeslagen.', photo_bad: 'Dit bestand is geen leesbare afbeelding.',
      pl_taken: function (pl, ch) { return '“' + pl + '” wordt gestart door ' + ch + '. Aan dit figuurtje geven?'; },
      seen_n: function (n) { return n + ' keer gebruikt'; }, on_jooki: 'Op de Jooki',
      forget: 'Vergeten', forget_q: 'Dit figuurtje vergeten?',
      forget_text: 'Het verdwijnt uit de lijst en komt terug zodra het weer gebruikt wordt. De afspeellijst van het personage verandert niet.',
      saved: 'Opgeslagen', no_tokens: 'Nog geen bekend figuurtje.',
      other_chars: 'Personages zonder bekend figuurtje',
      device: 'Apparaat', device_name: 'Naam', battery: 'Batterij', charging: 'aan het opladen', plugged: 'aangesloten',
      name_title: 'Naam van de Jooki op het netwerk',
      name_help: function (f) { return 'Kleine letters, cijfers en koppeltekens. De pagina wordt bereikbaar op naam.local. Laat leeg om terug te gaan naar de oorspronkelijke naam (' + f + ').'; },
      name_invalid: 'Alleen kleine letters, cijfers en koppeltekens (maximaal 32), geen koppelteken aan het begin of einde.',
      name_done: function (n) { return 'De Jooki heet nu ' + n; },
      name_text: function (u) { return 'De pagina staat nu op ' + u + ' — het oude adres antwoordt niet meer. Sla deze link op als bladwijzer. Spotify toont de nieuwe naam na de volgende herstart.'; },
      name_open: 'Het nieuwe adres openen',
      wifi: 'Wifi', ip: 'IP-adres', storage: 'Opslag', free: 'vrij', version: 'Versie',
      playback: 'Afspelen', toy_safe: 'Begrensd volume (kindermodus)', shuffle: 'Willekeurig', repeat: 'Herhalen',
      language: 'Taal', power_off: 'De Jooki uitzetten', power_off_q: 'De Jooki uitzetten?',
      power_off_text: 'Je moet op de knop drukken om hem weer aan te zetten.', power_off_done: 'De Jooki gaat uit…',
      nothing_playing: 'Er speelt niets', nothing_hint: 'Zet een figuurtje neer of kies een afspeellijst',
      live: 'Live', volume: 'Volume',
      uploading: 'Uploaden', processing: 'Verwerken op de Jooki…', done: 'Toegevoegd', queued: 'Wachten',
      up_too_small: 'Leeg of te klein bestand', up_no_space: 'Niet genoeg ruimte over op de Jooki',
      up_net: 'Upload mislukt (verbinding verbroken?)', up_type: 'Dit bestand is geen ondersteund audioformaat',
      up_fail: 'De Jooki kon dit bestand niet toevoegen', up_timeout: 'Geen antwoord van de Jooki',
      uploads_running: 'Er zijn uploads bezig. Als je de pagina verlaat, stoppen ze.',
      clear_done: 'Voltooide uploads verbergen',
      up_retrying: function (n, m) { return 'Verbinding verbroken, opnieuw proberen (' + n + '/' + m + ')…'; }, up_retry: 'Opnieuw',
      wifi_good: 'Goed signaal', wifi_fair: 'Matig signaal', wifi_weak: 'Zwak signaal',
      wifi_drops: function (n) { return n + (n === 1 ? ' onderbreking' : ' onderbrekingen') + ' sinds het opstarten'; },
      wifi_advice: 'Zet de Jooki dichter bij een wifi-toegangspunt. Muziek werkt zonder wifi: alleen deze pagina en uploads hebben het nodig.',
      err_readonly: 'Niet mogelijk bij ongebruikte nummers.',
      err_internal: 'De Jooki liep tegen een fout aan. Probeer het opnieuw.',
      err_empty_title: 'De naam mag niet leeg zijn.',
      err_radio: 'Ongeldig radioadres.',
      err_gone: 'Dit item bestaat niet meer.',
      err_generic: 'De Jooki heeft de actie geweigerd.',
      err_unknown_char: 'Onbekend personage.',
      duration_total: function (s) { return s; },
      mute_unsupported: '',
      files_hint: 'MP3, M4A, OGG, FLAC, WAV…',
      open_player: 'De speler openen',
      web_page: 'pagina', upd_check: 'Controleren op updates', upd_checking: 'Controleren…',
      upd_uptodate: 'Je Jooki is up-to-date.', upd_offline: 'GitHub is niet bereikbaar (is de Jooki online?).',
      upd_available: function (v) { return 'Nieuwe versie ' + v + ' beschikbaar'; }, upd_now: 'Nu bijwerken',
      upd_q: function (v) { return 'Bijwerken naar OpenJooki ' + v + '?'; },
      upd_text: 'De Jooki downloadt de nieuwe versie en start vanzelf opnieuw: tot 10 minuten. Laat hem aangesloten. Je muziek en figuurtjes blijven bewaard, en hij gaat vanzelf terug naar de vorige versie als er iets misgaat.',
      upd_running: 'Bijwerken…', upd_keep: 'Laat de Jooki aangesloten. Deze pagina maakt vanzelf opnieuw verbinding.',
      upd_rebooting: 'De Jooki start opnieuw op met de nieuwe versie…', upd_done: function (v) { return 'Jooki bijgewerkt: OpenJooki ' + v; },
      upd_failed: 'De update is niet gelukt. Je Jooki is niet veranderd.', upd_banner: function (v) { return 'Update ' + v + ' beschikbaar'; },
      upd_see: 'Bekijken',
      upd_steps: ['Nieuwe versie zoeken', 'Downloaden', 'Download controleren', 'Installeren (laat de Jooki aangesloten)', 'Installatie controleren', 'Opnieuw opstarten met de nieuwe versie'],
      bedtime: 'Bedtijd', sleep_timer: 'Slaaptimer', sleep_off: 'Uit',
      sleep_min: function (n) { return n + ' min'; }, sleep_track: 'Einde van het hoofdstuk',
      sleep_left: function (s) { return 'Stopt over ' + s; }, sleep_at_end: 'Stopt aan het einde van dit nummer',
      sleep_auto: 'automatisch (nachtmodus)', sleep_cancel: 'Timer annuleren',
      night_mode: 'Nachtmodus', night_help: 'In deze uren stopt elke luisterbeurt vanzelf, is het volume begrensd en zijn de lampjes gedimd.',
      night_from: 'Van', night_to: 'Tot', night_timer: 'Automatische timer', night_timer_none: 'Geen',
      night_maxvol: 'Maximaal volume', night_nolimit: 'geen limiet', night_dim: 'Gedimde lampjes',
      night_now: 'Nachtmodus is nu actief', night_next: function (h) { return 'Begint om ' + h; },
      night_clock: 'De Jooki haalt de tijd van het internet (inclusief zomertijd).',
      resume_at: function (c, s) { return 'Gaat verder bij hoofdstuk ' + c + (s ? ' · ' + s : ''); },
      resume_restart: 'Opnieuw vanaf het begin', resume_done: 'Gaat verder bij hoofdstuk 1',
      sort: 'Sorteren', sort_title: 'De afspeellijst op volgorde zetten', sorted: 'Nummers terug op volgorde gezet',
      sort_by_name: 'Bestandsnaam (1, 2, 3…)', sort_by_title: 'Titel', sort_by_artist: 'Artiest', sort_by_album: 'Album', sort_by_duration: 'Duur',
      sort_again: 'Tik nog eens op hetzelfde criterium om de volgorde om te keren.', sort_preview: 'Voorbeeld van de nieuwe volgorde',
      sort_apply: 'Deze volgorde vastleggen', sort_same: 'De afspeellijst staat al in deze volgorde',
      my_jooki: 'Mijn Jooki', bytes: ['B', 'kB', 'MB', 'GB'],
      n_tokens: function (n) { return n + (n === 1 ? ' figuurtje' : ' figuurtjes'); },
      sec_title: 'Beveiliging',
      ssh_label: 'Onderhoudstoegang (SSH)', ssh_help: 'Voor knutselaars. Gaat na een uur vanzelf uit.', ssh_on: 'aan (1 u)',
      mqtt_label: 'Domotica (MQTT op het netwerk)', mqtt_help: 'Voor Home Assistant. Standaard uit.',
      mqtt_host_l: 'Host', mqtt_port_l: 'Poort', mqtt_user_l: 'Gebruiker', mqtt_pass_l: 'Wachtwoord',
      parent_label: 'Oudercode', parent_help: 'Een 4-cijferige code voorkomt dat kinderen en gasten instellingen wijzigen (afspeellijst verwijderen, wifi, een update starten).',
      parent_set: 'Code instellen', parent_change: 'Code wijzigen', parent_off: 'Uitschakelen',
      parent_prompt: 'Voer de oudercode in', parent_new: '4-cijferige code', parent_cur: 'Huidige code', parent_bad: 'Onjuiste code',
      parent_reset: 'Code vergeten? Houd ◀ en ▶ 10 seconden samen ingedrukt op de Jooki.'
    }
  };
  var LANGS = [['en', 'English'], ['fr', 'Français'], ['nl', 'Nederlands']];
  function lsGet(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }
  function lsSet(k, v) { try { localStorage.setItem(k, v); } catch (e) {} }
  // English by default; French or Dutch only when the browser itself is set to that language
  var lang = lsGet('oj.lang') || (navigator.language || 'en').slice(0, 2).toLowerCase();
  if (!T[lang]) lang = 'en';
  function t(k) {
    var v = T[lang][k];
    if (v === undefined) v = T.fr[k];
    if (typeof v === 'function') return v.apply(null, Array.prototype.slice.call(arguments, 1));
    return v === undefined ? k : v;
  }

  /* ------------------------------------------------------------------ characters */
  var MEDIA = '/static/media/';
  var CHARS = [
    ['Jooki.Dragon', 'Dragon', 'Dragon', 'dragon.cffed3d7.png'],
    ['Jooki.Fox', 'Renard', 'Fox', 'fox.ac721aec.png'],
    ['Jooki.Ghost', 'Fantôme', 'Ghost', 'ghost.c2a43882.png'],
    ['Jooki.Knight', 'Chevalier', 'Knight', 'knight.dc50962b.png'],
    ['Jooki.Whale', 'Baleine', 'Whale', 'whale.da72da11.png'],
    ['Jooki.Black.Dragon', 'Dragon noir', 'Black dragon', 'dragon-black.27a71b2c.png'],
    ['Jooki.Black.Fox', 'Renard noir', 'Black fox', 'fox-black.7d23b82c.png'],
    ['Jooki.Black.Knight', 'Chevalier noir', 'Black knight', 'knight-black.d995170a.png'],
    ['Jooki.Black.Whale', 'Baleine noire', 'Black whale', 'whale-black.74e936a9.png'],
    ['Jooki.White.Dragon', 'Dragon blanc', 'White dragon', 'dragon-white.921a8110.png'],
    ['Jooki.White.Fox', 'Renard blanc', 'White fox', 'fox-white.8f5e5c27.png'],
    ['Jooki.White.Knight', 'Chevalier blanc', 'White knight', 'knight-white.b0dd9a37.png'],
    ['Jooki.White.Whale', 'Baleine blanche', 'White whale', 'whale-white.218d88b9.png'],
    ['G2.Orange', 'Jeton orange', 'Orange token', '#f28b24'],
    ['G2.DarkBlue', 'Jeton bleu foncé', 'Dark blue token', '#23408e'],
    ['G2.Turquoise', 'Jeton turquoise', 'Turquoise token', '#22b2ad'],
    ['G2.Yellow', 'Jeton jaune', 'Yellow token', '#f4c21b'],
    ['G2.Red', 'Jeton rouge', 'Red token', '#d7362c'],
    ['G2.Purple', 'Jeton violet', 'Purple token', '#7c4db4'],
    ['G2.Green', 'Jeton vert', 'Green token', '#3ba555'],
    ['G2.Pink', 'Jeton rose', 'Pink token', '#ec6ea6'],
    ['Jooki.Flat', 'Jeton plat', 'Flat token', 'flat.5534d75d.png'],
    ['Jooki.ThankYou', 'Jeton Merci', 'Thank-you token', 'flat.5534d75d.png']
  ];
  var CHAR = {};
  CHARS.forEach(function (c, i) { CHAR[c[0]] = { id: c[0], fr: c[1], en: c[2], art: c[3], order: i }; });
  function charInfo(id) {
    if (CHAR[id]) return CHAR[id];
    return { id: id, fr: id || '?', en: id || '?', art: null, order: 999 };
  }
  // a foreign NFC tag (amiibo, sticker) is its own character "tag.<uid>": named by its nickname, else "NFC tag" + the end of its id
  function foreignUid(id) { return id && id.indexOf('tag.') === 0 ? id.slice(4) : null; }
  function charName(id) {
    var uid = foreignUid(id);
    if (uid) { var tk = S.db.tokens[uid]; return (tk && tk.name) || (t('nfc_tag') + ' ' + uid.slice(-4)); }
    var c = charInfo(id); return c[lang] || c.fr;
  }
  function isUserChar(id) { return !!id && id.indexOf('sys.') !== 0 && id.indexOf('test.') !== 0; }

  /* ------------------------------------------------------------------ helpers */
  function h(tag, attrs) {
    var el = document.createElement(tag);
    if (attrs) {
      for (var k in attrs) {
        var v = attrs[k];
        if (v === null || v === undefined || v === false) continue;
        if (k === 'class') el.className = v;
        else if (k === 'text') el.textContent = v;
        else if (k === 'html') el.innerHTML = v; // only used with static SVG icons
        else if (k.slice(0, 2) === 'on') el.addEventListener(k.slice(2), v);
        else if (k === 'value') el.value = v;
        else if (k === 'checked') el.checked = !!v;
        else if (k === 'style') el.setAttribute('style', v);
        else el.setAttribute(k, v === true ? '' : v);
      }
    }
    for (var i = 2; i < arguments.length; i++) add(el, arguments[i]);
    return el;
  }
  function add(el, c) {
    if (c === null || c === undefined || c === false) return;
    if (Array.isArray(c)) { c.forEach(function (x) { add(el, x); }); return; }
    el.appendChild(typeof c === 'object' ? c : document.createTextNode(String(c)));
  }
  var ICONS = {
    list: '<path d="M4 6h16M4 12h16M4 18h10"/>',
    token: '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3"/>',
    lib: '<path d="M9 18V5l11-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="17" cy="16" r="3"/>',
    gear: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>',
    play: '<path d="M7 4.5v15l13-7.5z" fill="currentColor" stroke="none"/>',
    pause: '<path d="M7 4h4v16H7zM14 4h4v16h-4z" fill="currentColor" stroke="none"/>',
    next: '<path d="M5 5l10 7-10 7zM18 5v14" fill="currentColor"/>',
    prev: '<path d="M19 5L9 12l10 7zM6 5v14" fill="currentColor"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    upload: '<path d="M12 16V4M6 10l6-6 6 6M4 20h16"/>',
    radio: '<circle cx="12" cy="12" r="2"/><path d="M16.2 7.8a6 6 0 0 1 0 8.4M7.8 16.2a6 6 0 0 1 0-8.4M19 5a10 10 0 0 1 0 14M5 19A10 10 0 0 1 5 5"/>',
    trash: '<path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13"/>',
    x: '<path d="M6 6l12 12M18 6L6 18"/>',
    grip: '<path d="M9 6h.01M15 6h.01M9 12h.01M15 12h.01M9 18h.01M15 18h.01" stroke-width="3"/>',
    edit: '<path d="M4 20h4L19 9l-4-4L4 16z"/>',
    back: '<path d="M15 5l-7 7 7 7"/>',
    search: '<circle cx="11" cy="11" r="7"/><path d="M20 20l-4-4"/>',
    check: '<path d="M5 12l5 5 9-10"/>',
    book: '<path d="M4 5a2 2 0 0 1 2-2h13v16H6a2 2 0 0 0-2 2z"/><path d="M4 19V5"/>',
    shuffle: '<path d="M16 3h5v5M4 20L21 3M21 16v5h-5M15 15l6 6M4 4l5 5"/>',
    repeat: '<path d="M17 1l4 4-4 4"/><path d="M3 11V9a4 4 0 0 1 4-4h14M7 23l-4-4 4-4"/><path d="M21 13v2a4 4 0 0 1-4 4H3"/>',
    vol: '<path d="M11 5L6 9H2v6h4l5 4z"/><path d="M15.5 8.5a5 5 0 0 1 0 7M19 5a10 10 0 0 1 0 14"/>',
    power: '<path d="M12 2v10M18.4 6.6a9 9 0 1 1-12.8 0"/>',
    note: '<path d="M9 18V5l11-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="17" cy="16" r="3"/>',
    link0: '<path d="M8 12h8"/>',
    moon: '<path d="M20 14.5A8.5 8.5 0 0 1 9.5 4a8.5 8.5 0 1 0 10.5 10.5z"/>',
    sort: '<path d="M4 6h9M4 12h7M4 18h5M17 4v16M14 17l3 3 3-3"/>'
  };
  function icon(name) {
    var s = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    s.setAttribute('viewBox', '0 0 24 24');
    s.setAttribute('fill', 'none');
    s.setAttribute('stroke', 'currentColor');
    s.setAttribute('stroke-width', '2');
    s.setAttribute('stroke-linecap', 'round');
    s.setAttribute('stroke-linejoin', 'round');
    s.setAttribute('aria-hidden', 'true');
    s.innerHTML = ICONS[name] || '';
    return s;
  }
  function fmtTime(sec) {
    sec = Math.max(0, Math.round(Number(sec) || 0));
    var hh = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60;
    if (hh) return hh + ':' + (m < 10 ? '0' : '') + m + ':' + (s < 10 ? '0' : '') + s;
    return m + ':' + (s < 10 ? '0' : '') + s;
  }
  function fmtTotal(sec) {
    sec = Math.round(Number(sec) || 0);
    var hh = Math.floor(sec / 3600), m = Math.round((sec % 3600) / 60);
    if (hh) return hh + ' h ' + (m < 10 ? '0' : '') + m;
    return m + ' min';
  }
  function fmtBytes(b) {
    b = Number(b) || 0;
    var u = t('bytes');
    var i = 0;
    while (b >= 1000 && i < u.length - 1) { b /= 1000; i++; }
    return (i ? b.toFixed(b < 10 ? 1 : 0) : b) + ' ' + u[i];
  }
  function obj(x) { return x && typeof x === 'object' && !Array.isArray(x) ? x : {}; }
  function arr(x) { return Array.isArray(x) ? x : []; }
  function cleanTitle(s) { return String(s || '').replace(/\.(mp3|m4a|mp4|aac|ogg|oga|flac|wav|wma)$/i, ''); }
  function collator() { try { return new Intl.Collator(lang, { numeric: true, sensitivity: 'base' }); } catch (e) { return { compare: function (a, b) { return a < b ? -1 : a > b ? 1 : 0; } }; } }

  /* ------------------------------------------------------------------ state */
  var S = { db: { playlists: {}, tracks: {}, tokens: {} }, audio: { config: {}, playback: {}, nowPlaying: {} }, nfc: {}, device: {}, power: {}, wifi: {}, userMessages: [], bedtime: {}, maintenance: {} };
  var gotState = false;
  function normalize() {
    S.db = obj(S.db);
    S.db.playlists = obj(S.db.playlists);
    S.db.tracks = obj(S.db.tracks);
    S.db.tokens = obj(S.db.tokens);
    delete S.db.tokens._;
    S.audio = obj(S.audio);
    S.audio.config = obj(S.audio.config);
    S.audio.playback = obj(S.audio.playback);
    S.audio.nowPlaying = obj(S.audio.nowPlaying);
    S.nfc = obj(S.nfc); S.device = obj(S.device); S.power = obj(S.power); S.wifi = obj(S.wifi);
    S.userMessages = arr(S.userMessages);
    S.net = obj(S.net);
    S.bedtime = obj(S.bedtime);
    S.bedtime.cfg = obj(S.bedtime.cfg);
    S.bedtime.resume = obj(S.bedtime.resume);
  }
  function mergeState(p) {
    if (!p || typeof p !== 'object') return;
    Object.keys(p).forEach(function (k) {
      if (k === 'audio' && p.audio && typeof p.audio === 'object' && !Array.isArray(p.audio)) {
        S.audio = obj(S.audio);
        Object.keys(p.audio).forEach(function (s) { S.audio[s] = p.audio[s]; });
        if (p.audio.playback) posStamp = Date.now();
      } else if (k === 'bedtime') {
        S.bedtime = p.bedtime;
        sleepStamp = Date.now();
      } else {
        S[k] = p[k];
      }
    });
    if (p.db) gotState = true;
    normalize();
  }
  var posStamp = Date.now(), sleepStamp = Date.now();
  function pls() { return S.db.playlists; }
  function userPlaylists() {
    var c = collator();
    return Object.keys(pls()).filter(function (id) { return id !== 'TRASH' && id !== 'system'; })
      .map(function (id) { return Object.assign({ id: id }, pls()[id]); })
      .sort(function (a, b) { return c.compare(a.title || '', b.title || ''); });
  }
  function trackTitle(id) { var tr = S.db.tracks[id]; if (!tr) return '?'; return cleanTitle(tr.title || tr.userFilename || id); }
  function trackSub(tr) {
    if (!tr) return '';
    if (tr.isUrl) return t('radio') + ' · ' + (tr.filename || '');
    var bits = [];
    if (tr.artist && tr.artist !== 'unknown') bits.push(tr.artist);
    if (tr.album && tr.album !== 'unknown') bits.push(tr.album);
    if (tr.duration) bits.push(fmtTime(tr.duration));
    return bits.join(' · ');
  }
  function playlistOfChar(starId) {
    var list = userPlaylists();
    for (var i = 0; i < list.length; i++) if (list[i].star === starId) return list[i];
    return null;
  }
  function unusedIds() { var tr = pls().TRASH; return tr ? arr(tr.tracks).filter(function (x) { return S.db.tracks[x]; }) : []; }

  /* ------------------------------------------------------------------ MQTT connection */
  var client = null, online = false, everOnline = false, retryDelay = 1000, retryTimer = null, lastCmd = 0;
  var wsHost = location.hostname || '127.0.0.1';
  // The broker's WebSocket needs a per-Jooki password (docs/adr/0007). It is served
  // at the page's own origin: readable here, not by a booby-trapped website (no CORS,
  // and JSON is not runnable as a <script>). Fetched once at boot; if it is absent
  // (an older or un-hardened Jooki), we connect anonymously as before. Reconnects
  // reuse CFG, so this runs only at startup.
  function loadAuth(then) {
    if (!window.fetch) { then(); return; }
    var done = false, cont = function () { if (!done) { done = true; then(); } };
    setTimeout(cont, 4000);
    fetch('oj-auth.json', { cache: 'no-store', credentials: 'same-origin' })
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (c) {
        if (c && typeof c === 'object') {
          if (c.mqttUser != null) CFG.mqttUser = c.mqttUser;
          if (c.mqttPass != null) CFG.mqttPass = c.mqttPass;
          if (c.wsPort != null) CFG.wsPort = c.wsPort;
        }
        cont();
      })
      .catch(cont);
  }
  function connect() {
    clearTimeout(retryTimer);
    if (client) { try { client.onclose = function () {}; client.close(); } catch (e) {} }
    var url = 'ws://' + (wsHost.indexOf(':') >= 0 ? '[' + wsHost + ']' : wsHost) + ':' + (CFG.wsPort || 8000) + '/mqtt';
    client = new window.MiniMqtt(url, { username: CFG.mqttUser, password: CFG.mqttPass, keepalive: 20 });
    client.onconnect = function () {
      online = true; everOnline = true; retryDelay = 1000;
      client.subscribe('/j/web/output/#');
      send('GET_STATE', {});
      render();
    };
    client.onmessage = onMessage;
    client.onclose = function () {
      var was = online;
      online = false;
      uploads.forEach(function (u) { if (u.status === 'processing') u.lost = true; });
      if (was || !everOnline) render();
      retryTimer = setTimeout(connect, retryDelay);
      retryDelay = Math.min(retryDelay * 1.6, 8000);
    };
    client.connect();
  }
  // parent code (docs/adr/0007): remembered once per device, sent with every command;
  // the Jooki only checks it on the actions it protects. Playing music never needs it.
  var parentCode = lsGet('oj.parent') || '';
  var pendingCmd = null;
  function send(type, payload) {
    lastCmd = Date.now();
    if (!client || !online) { toast(t('offline'), 'error'); return false; }
    payload = payload || {};
    if (parentCode) payload.code = parentCode;
    pendingCmd = { type: type, payload: payload };
    return client.publish('/j/web/input/' + type, JSON.stringify(payload));
  }
  var waiters = [], autoChecked = false;
  function onMessage(topic, text) {
    var data;
    try { data = JSON.parse(text); } catch (e) { return; }
    if (topic === '/j/web/output/state') {
      var posOnly = data && Object.keys(data).length === 1 && data.audio && Object.keys(data.audio).length === 1 && data.audio.playback &&
        obj(data.audio.playback).state === S.audio.playback.state;
      mergeState(data);
      if (posOnly) return;
      waiters = waiters.filter(function (w) { return !w(data); });
      if (!autoChecked && S.device.openjooki) { autoChecked = true; setTimeout(checkUpdate, 1500); }
      syncClock();
      handleUserMessages();
      scheduleRender();
    } else if (topic === '/j/web/output/error') {
      if (data && data.msg === 'PARENT_CODE_REQUIRED') {
        var bad = !!parentCode;                       // a stored code that no longer matches
        if (bad) { parentCode = ''; lsSet('oj.parent', ''); }
        askParent(bad);
        return;
      }
      if (Date.now() - lastCmd < 4000) toast(errorText(data && data.msg), 'error');
    }
  }
  function errorText(msg) {
    msg = String(msg || '');
    if (msg === 'TRASH_READONLY') return t('err_readonly');
    if (msg === 'ERR_INTERNAL') return t('err_internal');
    if (msg === 'empty title') return t('err_empty_title');
    if (msg === 'invalid stream url') return t('err_radio');
    if (msg === 'invalid token type') return t('err_unknown_char');
    if (/does not exist|invalid:|nil playlistId|unknown token/.test(msg)) return t('err_gone');
    return t('err_generic');
  }
  var seenMsg = {};
  function handleUserMessages() {
    S.userMessages.forEach(function (m) {
      if (!m || seenMsg[m.id]) return;
      seenMsg[m.id] = true;
      var type = String(m.messageType || '');
      var ex = obj(m.extra);
      var mine = uploads.some(function (u) { return u.name === ex.filename && (u.status === 'processing' || u.status === 'uploading'); });
      if (type.indexOf('UPLOAD_FAIL') === 0) {
        uploads.forEach(function (u) {
          if (u.name === ex.filename && u.status === 'processing') { u.failType = type; }
        });
        if (!mine && ex.filename) toast(t(type === 'UPLOAD_FAIL_TYPE' ? 'up_type' : 'up_fail') + ' : ' + ex.filename, 'error');
      }
      if (client && online) client.publish('/j/web/input/MESSAGE_DISMISS', JSON.stringify({ id: m.id }));
    });
  }

  /* ------------------------------------------------------------------ toasts & modals */
  var toastBox;
  function toast(text, kind, action) {
    if (!toastBox) return;
    var el = h('div', { class: 'toast' + (kind === 'error' ? ' error' : ''), role: 'status' }, h('span', { class: 'grow' }, text));
    if (action) el.appendChild(h('button', { onclick: function () { action.fn(); el.remove(); } }, action.label));
    toastBox.appendChild(el);
    setTimeout(function () { el.remove(); }, action ? 6000 : 3500);
  }
  var modal = null; // {render: fn -> element, onclose}
  function openModal(m) { modal = m; renderModal(); }
  function closeModal() { var m = modal; modal = null; renderModal(); if (m && m.onclose) m.onclose(); }
  var modalRoot, modalRendering = false;   // true while a sheet is rebuilt: its inputs blur without meaning it
  function renderModal() {
    if (!modalRoot) return;
    var keep = captureFocus(modalRoot);
    modalRendering = true;
    try {
      modalRoot.innerHTML = '';
      if (!modal) { document.body.style.overflow = ''; return; }
      document.body.style.overflow = 'hidden';
      var sheet = h('div', { class: 'sheet', role: 'dialog', 'aria-modal': 'true' }, modal.render());
      var ov = h('div', { class: 'overlay', onclick: function (e) { if (e.target === ov) closeModal(); } }, sheet);
      modalRoot.appendChild(ov);
      restoreFocus(modalRoot, keep, modal.autofocus);
    } finally { modalRendering = false; }
  }
  function confirmBox(title, text, okLabel, danger) {
    return new Promise(function (resolve) {
      var done = false;
      function fin(v) { if (done) return; done = true; modal = null; renderModal(); resolve(v); }
      openModal({
        onclose: function () { fin(false); },
        render: function () {
          return [h('h3', null, title), text ? h('p', { class: 'muted' }, text) : null,
            h('div', { class: 'foot' },
              h('button', { class: 'btn', onclick: function () { fin(false); } }, t('cancel')),
              h('button', { class: 'btn ' + (danger ? 'danger solid' : 'primary'), 'data-k': 'ok', onclick: function () { fin(true); } }, okLabel))];
        },
        autofocus: 'ok'
      });
    });
  }
  function captureFocus(root) {
    var a = document.activeElement;
    if (!a || !root.contains(a) || !a.getAttribute('data-k')) return null;
    return { k: a.getAttribute('data-k'), s: a.selectionStart, e: a.selectionEnd };
  }
  function restoreFocus(root, keep, auto) {
    var k = keep ? keep.k : auto;
    if (!k) return;
    var el = root.querySelector('[data-k="' + k + '"]');
    if (!el) return;
    el.focus({ preventScroll: true });
    if (keep && keep.s !== undefined && keep.s !== null && el.setSelectionRange) { try { el.setSelectionRange(keep.s, keep.e); } catch (e) {} }
  }

  document.addEventListener('keydown', function (e) { if (e.key === 'Escape' && modal) closeModal(); });

  /* ------------------------------------------------------------------ uploads */
  var uploads = [], upBusy = false, upSeq = 0;
  var AUDIO_EXT = /\.(mp3|m4a|mp4|aac|ogg|oga|flac|wav|wma|m4b)$/i;
  function enqueue(files, playlistId) {
    var free = S.device.diskUsage && Number(S.device.diskUsage.available) ? Number(S.device.diskUsage.available) * 1024 : null;
    var reserved = 0;
    Array.prototype.forEach.call(files, function (f) {
      var u = { key: ++upSeq, file: f, name: f.name, size: f.size, playlistId: playlistId || null, status: 'queued', progress: 0, error: null };
      if (f.size <= 5000) { u.status = 'error'; u.error = t('up_too_small'); }
      else if (!AUDIO_EXT.test(f.name) && !(f.type && f.type.indexOf('audio/') === 0)) { u.status = 'error'; u.error = t('up_type'); }
      else if (free !== null && reserved + f.size + 10e6 > free) { u.status = 'error'; u.error = t('up_no_space'); }
      else reserved += f.size;
      uploads.push(u);
    });
    render();
    pump();
  }
  // A weak Wi-Fi drops connections: a failed or stalled transfer is retried on its own
  // (after the Jooki is back), and a lost answer is checked again after reconnecting.
  var UP_TRIES = 4, UP_STALL_MS = 30000, UP_DELAYS = [3000, 8000, 20000];
  function pump() {
    if (upBusy) return;
    var now = Date.now();
    var u = uploads.filter(function (x) { return x.status === 'queued' && !(x.retryAt > now); })[0];
    if (!u) {
      var next = uploads.filter(function (x) { return x.status === 'queued'; }).map(function (x) { return x.retryAt; })[0];
      if (next) setTimeout(pump, Math.max(200, next - now));
      return;
    }
    if (!online) { setTimeout(pump, 1500); return; }
    upBusy = true;
    u.status = 'uploading'; u.progress = 0; u.tries = (u.tries || 0) + 1; u.note = null;
    var uid = String(Math.floor(Math.random() * 9e6) + 1e6);
    var fd = new FormData();
    fd.append(uid, u.file, u.name);
    var xhr = new XMLHttpRequest();
    var lastMove = Date.now(), ended = false;
    var stall = setInterval(function () { if (Date.now() - lastMove > UP_STALL_MS) { xhr.abort(); } }, 2000);
    function netFail(why) {
      if (ended) return; ended = true; clearInterval(stall);
      retryOrFail(u, why);
    }
    xhr.open('POST', '/upload');
    xhr.upload.onprogress = function (e) { lastMove = Date.now(); if (e.lengthComputable) { u.progress = e.loaded / e.total; updateUploadRow(u); } };
    xhr.onerror = xhr.ontimeout = xhr.onabort = function () { netFail(t('up_net')); };
    xhr.onload = function () {
      if (ended) return; ended = true; clearInterval(stall);
      if (xhr.status !== 200) { retryOrFail(u, t('up_net') + ' (' + xhr.status + ')'); return; }
      u.progress = 1;
      u.status = 'processing';
      render();
      var beforePl = u.playlistId && pls()[u.playlistId] ? arr(pls()[u.playlistId].tracks).length : -1;
      var beforeLib = Object.keys(S.db.tracks).length;
      var p = { uploadId: uid, filename: u.name };
      if (u.playlistId) p.playlistId = u.playlistId;
      var resent = false;
      u.lost = false;
      var timer = setTimeout(function () { finishUp(u, 'error', t('up_timeout')); }, 240000);
      function added() {
        if (u.playlistId) return pls()[u.playlistId] && arr(pls()[u.playlistId].tracks).length > beforePl;
        return Object.keys(S.db.tracks).length > beforeLib;
      }
      waiters.push(function (partial) {
        if (u.status !== 'processing') return true;
        if (partial.audio) {                 // full state after a reconnection: did the Jooki get it?
          if (!u.lost) return false;
          u.lost = false;
          if (added()) { clearTimeout(timer); finishUp(u, 'done'); return true; }
          if (!resent) { resent = true; send('PLAYLIST_ADD_UPLOAD', p); }
          return false;
        }
        if (!(partial.db && partial.device)) return false; // end of an upload request
        clearTimeout(timer);
        if (u.failType) { finishUp(u, 'error', t(u.failType === 'UPLOAD_FAIL_TYPE' ? 'up_type' : 'up_fail')); return true; }
        if (u.playlistId && pls()[u.playlistId] && arr(pls()[u.playlistId].tracks).length <= beforePl) {
          if (resent && !u.failType) { finishUp(u, 'done'); return true; } // first request had worked
          finishUp(u, 'error', t('up_fail')); return true;
        }
        finishUp(u, 'done');
        return true;
      });
      if (!send('PLAYLIST_ADD_UPLOAD', p)) u.lost = true;
    };
    xhr.send(fd);
    render();
  }
  function retryOrFail(u, why) {
    upBusy = false;
    if (u.tries < UP_TRIES && u.file) {
      u.status = 'queued'; u.progress = 0;
      u.retryAt = Date.now() + UP_DELAYS[Math.min(u.tries - 1, UP_DELAYS.length - 1)];
      u.note = t('up_retrying', u.tries + 1, UP_TRIES);
      render(); setTimeout(pump, 50);
      return;
    }
    u.status = 'error'; u.error = why; u.canRetry = !!u.file;
    render(); setTimeout(pump, 50);
  }
  function retryUpload(u) { u.status = 'queued'; u.tries = 0; u.retryAt = 0; u.error = null; u.canRetry = false; render(); pump(); }
  function finishUp(u, status, err) {
    if (u.status === 'done' || u.status === 'error') return;
    u.status = status; u.error = err || null; u.file = null; u.note = null;
    upBusy = false;
    render();
    setTimeout(pump, 50);
  }
  function uploadsActive() { return uploads.some(function (u) { return u.status === 'queued' || u.status === 'uploading' || u.status === 'processing'; }); }
  window.addEventListener('beforeunload', function (e) { if (uploadsActive()) { e.preventDefault(); e.returnValue = t('uploads_running'); return e.returnValue; } });
  function updateUploadRow(u) {
    var el = document.querySelector('[data-up="' + u.key + '"] .bar > i');
    if (el) el.style.width = Math.round(u.progress * 100) + '%';
    var st = document.querySelector('[data-up="' + u.key + '"] .st');
    if (st) st.textContent = t('uploading') + ' ' + Math.round(u.progress * 100) + ' %';
  }
  function uploadsBlock(playlistId) {
    var list = uploads.filter(function (u) { return u.playlistId === (playlistId || null); });
    if (!list.length) return null;
    var anyDone = list.some(function (u) { return u.status === 'done' || u.status === 'error'; });
    return h('div', { class: 'card uploads' },
      list.map(function (u) {
        var st = u.status === 'queued' ? (u.note || t('queued')) : u.status === 'uploading' ? t('uploading') + ' ' + Math.round(u.progress * 100) + ' %'
          : u.status === 'processing' ? t('processing') : u.status === 'done' ? t('done') : u.error;
        return h('div', { class: 'up ' + u.status, 'data-up': u.key },
          h('div', { class: 'row' }, h('div', { class: 'grow ellipsis' }, u.name), h('span', { class: 'small muted' }, fmtBytes(u.size))),
          h('div', { class: 'bar' }, h('i', { style: 'width:' + (u.status === 'done' || u.status === 'processing' ? 100 : Math.round(u.progress * 100)) + '%' })),
          h('div', { class: 'st row' }, h('span', { class: 'grow' }, st),
            u.status === 'error' && u.canRetry ? h('button', { class: 'btn ghost', 'data-k': 'upretry-' + u.key, onclick: function () { retryUpload(u); } }, t('up_retry')) : null));
      }),
      anyDone && !uploadsActive() ? h('div', { class: 'up' }, h('button', { class: 'btn ghost block', onclick: function () {
        uploads = uploads.filter(function (u) { return u.playlistId !== (playlistId || null) || (u.status !== 'done' && u.status !== 'error'); }); render();
      } }, t('clear_done'))) : null);
  }
  function fileButton(label, playlistId, primary) {
    var inp = h('input', { type: 'file', multiple: true, accept: 'audio/*,.mp3,.m4a,.m4b,.aac,.ogg,.oga,.flac,.wav,.wma', class: 'sr', 'aria-hidden': 'true', tabindex: '-1',
      onchange: function () { if (inp.files && inp.files.length) enqueue(inp.files, playlistId); inp.value = ''; } });
    return h('label', { class: 'btn' + (primary ? ' primary' : ''), tabindex: '0', role: 'button',
      onkeydown: function (e) { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); inp.click(); } } }, icon('upload'), label, inp);
  }
  function dropZone(playlistId) {
    var z = h('div', { class: 'drop' }, t('drop_here'), h('div', { class: 'small' }, t('files_hint')));
    z.addEventListener('dragover', function (e) { e.preventDefault(); z.classList.add('over'); });
    z.addEventListener('dragleave', function () { z.classList.remove('over'); });
    z.addEventListener('drop', function (e) { e.preventDefault(); z.classList.remove('over'); if (e.dataTransfer && e.dataTransfer.files.length) enqueue(e.dataTransfer.files, playlistId); });
    return z;
  }
  var canHover = window.matchMedia && window.matchMedia('(hover: hover) and (pointer: fine)').matches;

  /* ------------------------------------------------------------------ token visuals */
  function tokVisual(starId, cls, live) {
    var c = charInfo(starId);
    var el = h('div', { class: 'tok ' + (cls || '') + (live ? ' live' : ''), title: charName(starId) });
    if (!starId) { el.className += ' none'; el.appendChild(icon('token')); return el; }
    var fu = foreignUid(starId), ftk = fu && S.db.tokens[fu];
    if (ftk && ftk.image) {   // the picture given to a tag (a 128 px PNG on the Jooki, see tokenImageEditor)
      var pic = h('img', { src: ftk.image, alt: '' });
      pic.onerror = function () { pic.replaceWith(h('span', { class: 'letter' }, (charName(starId) || '?').charAt(0))); };
      el.appendChild(pic); return el;
    }
    if (c.art && c.art.charAt(0) === '#') el.appendChild(h('div', { class: 'disc', style: 'background:' + c.art }));
    else if (c.art) {
      var img = h('img', { src: MEDIA + c.art, alt: '' });
      img.onerror = function () { img.replaceWith(h('span', { class: 'letter' }, (charName(starId) || '?').charAt(0))); };
      el.appendChild(img);
    } else el.appendChild(h('span', { class: 'letter' }, (charName(starId) || '?').charAt(0)));
    return el;
  }

  /* ------------------------------------------------------------------ routing */
  function route() {
    var hs = (location.hash || '#/').replace(/^#/, '');
    var parts = hs.split('/').filter(Boolean).map(function (x) { try { return decodeURIComponent(x); } catch (e) { return x; } });
    return { name: parts[0] || 'playlists', arg: parts[1] || null };
  }
  function go(hash) { if (location.hash !== hash) location.hash = hash; else render(); }
  window.addEventListener('hashchange', function () { ui.sel = {}; ui.search = ''; ui.editTitle = null; window.scrollTo(0, 0); render(); });

  /* ------------------------------------------------------------------ UI state */
  var ui = { search: '', sel: {}, editTitle: null, dragging: false, libTab: 'all' };

  /* ------------------------------------------------------------------ views */
  function viewPlaylists() {
    var list = userPlaylists();
    var np = S.audio.nowPlaying;
    var un = unusedIds().length;
    var cards = list.map(function (p) {
      var n = arr(p.tracks).length;
      var total = arr(p.tracks).reduce(function (s, x) { var tr = S.db.tracks[x]; return s + (tr && !tr.isUrl ? Number(tr.duration) || 0 : 0); }, 0);
      var card = h('div', { class: 'card pl' + (np.playlistId === p.id ? ' active' : ''), role: 'link', tabindex: '0', 'data-pl': p.id,
        onclick: function () { go('#/p/' + encodeURIComponent(p.id)); },
        onkeydown: function (e) { if (e.key === 'Enter') go('#/p/' + encodeURIComponent(p.id)); } },
        h('div', { class: 'ph' }, tokVisual(p.star, 'sm', S.nfc.starId && S.nfc.starId === p.star)),
        h('div', { class: 'name' }, p.title || '—'),
        h('div', { class: 'meta' }, t('n_tracks', n) + (total ? ' · ' + fmtTotal(total) : '') + (p.audiobook ? ' · ' + t('audiobook') : '')),
        n ? h('button', { class: 'icon-btn accent play', 'aria-label': t('play') + ' ' + (p.title || ''), onclick: function (e) {
          e.stopPropagation(); send('PLAYLIST_PLAY', { playlistId: p.id }); } }, icon('play')) : null);
      return card;
    });
    cards.push(h('button', { class: 'card pl newpl', onclick: newPlaylistModal, 'data-k': 'newpl' }, icon('plus'), t('new_playlist')));
    return [
      updateAvailable() && upd.state === 'checked' ? h('div', { class: 'banner row', 'data-k': 'updbanner' }, h('span', { class: 'grow' }, t('upd_banner', upd.latest)),
        h('a', { href: '#/settings' }, t('upd_see'))) : null,
      un ? h('div', { class: 'banner row' }, h('span', { class: 'grow' }, t('unused_banner', un)),
        h('a', { href: '#/library/unused' }, t('see'))) : null,
      list.length ? null : h('div', { class: 'empty' }, h('div', { class: 'big' }, '🎵'), t('no_playlists')),
      h('div', { class: 'plgrid' }, cards)
    ];
  }

  function newPlaylistModal(prefillTracks) {
    var name = '';
    function create() {
      var v = name.trim();
      if (!v) return;
      var before = Object.keys(pls());
      closeModal();
      waiters.push(function (partial) {
        if (!partial.db) return false;
        var fresh = Object.keys(pls()).filter(function (k) { return before.indexOf(k) < 0 && k !== 'TRASH'; })[0];
        if (!fresh) return false;
        if (Array.isArray(prefillTracks) && prefillTracks.length) {
          send('PLAYLIST_UPDATE', { playlist: { id: fresh, tracks: prefillTracks } });
          toast(t('added', prefillTracks.length));
        } else go('#/p/' + encodeURIComponent(fresh));
        return true;
      });
      send('PLAYLIST_NEW', { title: v, audiobook: false });
    }
    openModal({
      autofocus: 'plname',
      render: function () {
        return [h('h3', null, t('new_playlist')),
          h('label', { class: 'field' }, h('span', null, t('name')),
            h('input', { class: 'input', 'data-k': 'plname', maxlength: '100', placeholder: t('playlist_name_ph'), value: name,
              oninput: function (e) { name = e.target.value; var b = document.querySelector('[data-k="plcreate"]'); if (b) b.disabled = !name.trim(); },
              onkeydown: function (e) { if (e.key === 'Enter') create(); } })),
          h('div', { class: 'foot' }, h('button', { class: 'btn', onclick: closeModal }, t('cancel')),
            h('button', { class: 'btn primary', 'data-k': 'plcreate', disabled: !name.trim(), onclick: create }, t('create')))];
      }
    });
  }

  function charPickerModal(p) {
    var chosen = p.star || null;
    var seen = {};
    Object.keys(S.db.tokens).forEach(function (k) { var s = S.db.tokens[k] && S.db.tokens[k].starId; if (isUserChar(s)) seen[s] = true; });
    function opt(id) {
      var other = id ? playlistOfChar(id) : null;
      if (other && other.id === p.id) other = null;
      return h('button', { class: 'charopt' + (chosen === id ? ' sel' : ''), 'data-char': id || 'none', 'aria-pressed': chosen === id ? 'true' : 'false',
        onclick: function () { chosen = id; renderModal(); } },
        tokVisual(id, 'sm'), h('div', null, id ? charName(id) : t('no_token')), other ? h('div', { class: 'taken' }, t('used_by', other.title || '—')) : null);
    }
    var ids = CHARS.map(function (c) { return c[0]; }).filter(function (id) { return id !== 'Jooki.ThankYou'; });
    Object.keys(seen).forEach(function (s) { if (ids.indexOf(s) < 0) ids.push(s); });
    ids.sort(function (a, b) { return (seen[b] ? 1 : 0) - (seen[a] ? 1 : 0) || charInfo(a).order - charInfo(b).order; });
    openModal({
      render: function () {
        var other = chosen ? playlistOfChar(chosen) : null;
        if (other && other.id === p.id) other = null;
        return [h('h3', null, t('token_for')), h('p', { class: 'small muted' }, t('token_help')),
          h('div', { class: 'chargrid' }, opt(null), ids.map(opt)),
          other ? h('div', { class: 'banner', style: 'margin-top:12px' }, t('token_moved', other.title || '—')) : null,
          h('div', { class: 'foot' }, h('button', { class: 'btn', onclick: closeModal }, t('cancel')),
            h('button', { class: 'btn primary', 'data-k': 'charsave', onclick: function () {
              if ((chosen || null) !== (p.star || null)) send('PLAYLIST_UPDATE', { playlist: { id: p.id, star: chosen || false } });
              closeModal();
            } }, t('save')))];
      }
    });
  }

  function viewPlaylist(id) {
    if (id === 'TRASH') { setTimeout(function () { go('#/library/unused'); }, 0); return []; }
    var p = pls()[id];
    if (!p) return h('div', { class: 'empty' }, h('p', null, t('playlist_missing')), h('a', { class: 'btn', href: '#/' }, t('back')));
    p = Object.assign({ id: id }, p);
    var tracks = arr(p.tracks);
    var np = S.audio.nowPlaying;
    var total = tracks.reduce(function (s, x) { var tr = S.db.tracks[x]; return s + (tr && !tr.isUrl ? Number(tr.duration) || 0 : 0); }, 0);
    var editing = ui.editTitle !== null;
    function saveTitle() {
      var v = (ui.editTitle || '').trim();
      if (!v) { toast(t('err_empty_title'), 'error'); return; }
      if (v !== p.title) send('PLAYLIST_UPDATE', { playlist: { id: id, title: v } });
      ui.editTitle = null; render();
    }
    var head = h('div', { class: 'card plhead' },
      h('button', { class: 'tokbtn', 'aria-label': t('choose_token'), onclick: function () { charPickerModal(p); }, 'data-k': 'tokbtn' },
        tokVisual(p.star, '', S.nfc.starId && S.nfc.starId === p.star)),
      h('div', { class: 'grow' },
        editing ? h('div', { class: 'edit-title' },
          h('input', { class: 'input', 'data-k': 'title', maxlength: '100', value: ui.editTitle, 'aria-label': t('name'),
            oninput: function (e) { ui.editTitle = e.target.value; },
            onkeydown: function (e) { if (e.key === 'Enter') saveTitle(); if (e.key === 'Escape') { e.stopPropagation(); ui.editTitle = null; render(); } } }),
          h('button', { class: 'icon-btn', 'aria-label': t('save'), onclick: saveTitle }, icon('check')),
          h('button', { class: 'icon-btn', 'aria-label': t('cancel'), onclick: function () { ui.editTitle = null; render(); } }, icon('x')))
          : h('h2', { class: 'row' }, h('span', { class: 'grow' }, p.title || '—'),
            h('button', { class: 'icon-btn', 'aria-label': t('rename'), 'data-k': 'renamebtn', onclick: function () { ui.editTitle = p.title || ''; render(); setTimeout(function () {
              var el = document.querySelector('[data-k="title"]'); if (el) { el.focus(); el.select(); } }, 0); } }, icon('edit'))),
        h('div', { class: 'small muted' }, (p.star ? charName(p.star) : t('no_token')) + ' · ' + t('n_tracks', tracks.length) + (total ? ' · ' + fmtTotal(total) : ''))));
    var actions = h('div', { class: 'actions' },
      tracks.length ? h('button', { class: 'btn primary', onclick: function () { send('PLAYLIST_PLAY', { playlistId: id }); } }, icon('play'), t('play')) : null,
      fileButton(t('add_files'), id, !tracks.length),
      h('button', { class: 'btn', onclick: function () { libraryPickerModal(p); } }, icon('lib'), t('from_library')),
      h('button', { class: 'btn', onclick: function () { radioModal(p); } }, icon('radio'), t('web_radio')),
      tracks.length > 1 ? h('button', { class: 'btn', 'data-k': 'sortbtn', onclick: function () { sortModal(p); } }, icon('sort'), t('sort')) : null);
    var list;
    if (!tracks.length) {
      list = h('div', { class: 'card empty' }, h('div', { class: 'big' }, '🎶'), h('div', null, t('empty_playlist')), h('div', { class: 'small' }, t('empty_playlist_hint')));
    } else {
      list = h('ul', { class: 'card list', 'data-list': 'tracks' }, tracks.map(function (tid, i) {
        var tr = S.db.tracks[tid];
        var playing = np.playlistId === id && np.trackIndex === i + 1;
        return h('li', { class: 'clickable' + (playing ? ' playing' : ''), 'data-i': i, 'data-track': tid,
          onclick: function (e) { if (e.target.closest('button,.handle')) return; send('PLAYLIST_PLAY', { playlistId: id, trackIndex: i + 1 }); } },
          h('span', { class: 'handle', 'aria-hidden': 'true', onpointerdown: function (e) { startDrag(e, id); } }, icon('grip')),
          h('span', { class: 'num' }, playing ? '♪' : String(i + 1)),
          h('div', { class: 'grow' }, h('div', { class: 'title ellipsis' }, trackTitle(tid)), h('div', { class: 'sub ellipsis' }, trackSub(tr))),
          h('button', { class: 'icon-btn', 'aria-label': t('removed_from') + ' : ' + trackTitle(tid), 'data-remove': i, onclick: function () {
            var old = tracks.slice();
            var nt = tracks.slice(); nt.splice(i, 1);
            optimisticTracks(id, nt);
            send('PLAYLIST_UPDATE', { playlist: { id: id, tracks: nt } });
            toast(t('removed_from'), null, { label: t('undo'), fn: function () { optimisticTracks(id, old); send('PLAYLIST_UPDATE', { playlist: { id: id, tracks: old } }); } });
          } }, icon('x')));
      }));
    }
    var rs = p.audiobook ? S.bedtime.resume[id] : null;
    var ri = rs ? tracks.indexOf(rs.id) : -1;
    var more = h('div', { class: 'card', style: 'margin-top:16px' },
      h('label', { class: 'switch' }, h('div', null, h('div', null, t('audiobook')), h('div', { class: 'small muted' }, t('audiobook_help'))),
        h('input', { type: 'checkbox', role: 'switch', checked: !!p.audiobook, 'data-k': 'audiobook', onchange: function (e) { send('PLAYLIST_UPDATE', { playlist: { id: id, audiobook: e.target.checked } }); } })),
      p.audiobook && S.bedtime.cfg.start !== undefined && tracks.length ? h('div', { class: 'kv col', 'data-k': 'resume' },
        h('span', { class: 'muted' }, ri >= 0 ? t('resume_at', ri + 1, Number(rs.pos) > 20000 ? fmtTime((Number(rs.pos) - 15000) / 1000) : '') : t('resume_done')),
        ri >= 0 ? h('button', { class: 'btn ghost', 'data-k': 'resumereset', onclick: function () { send('OJ_RESUME_RESET', { playlistId: id }); } }, t('resume_restart')) : null) : null);
    var del = h('div', { class: 'actions' }, h('button', { class: 'btn danger', onclick: function () {
      confirmBox(t('delete_playlist_q', p.title || '—'), t('delete_playlist_text'), t('delete'), true).then(function (ok) {
        if (!ok) return;
        send('PLAYLIST_DELETE', { playlistId: id });
        go('#/');
      });
    } }, icon('trash'), t('delete_playlist')));
    return [head, actions, uploadsBlock(id), canHover ? dropZone(id) : null, list, more, del];
  }
  function optimisticTracks(id, tracks) { if (pls()[id]) { pls()[id].tracks = tracks; render(); } }

  /* drag & drop reorder (mouse + touch through pointer events) */
  var drag = null;
  function startDrag(e, playlistId) {
    var li = e.target.closest('li');
    if (!li) return;
    e.preventDefault();
    var ul = li.parentNode;
    var items = Array.prototype.slice.call(ul.children);
    var from = items.indexOf(li);
    var rect = li.getBoundingClientRect();
    drag = { li: li, ul: ul, from: from, to: from, startY: e.clientY, h: rect.height, id: playlistId, items: items, pointer: e.pointerId };
    ui.dragging = true;
    li.classList.add('dragging');
    try { li.setPointerCapture(e.pointerId); } catch (x) {}
    li.addEventListener('pointermove', onDragMove);
    li.addEventListener('pointerup', onDragEnd);
    li.addEventListener('pointercancel', onDragEnd);
  }
  function onDragMove(e) {
    if (!drag) return;
    var dy = e.clientY - drag.startY;
    drag.li.style.transform = 'translateY(' + dy + 'px)';
    var to = Math.max(0, Math.min(drag.items.length - 1, drag.from + Math.round(dy / drag.h)));
    drag.to = to;
    drag.items.forEach(function (it, i) {
      if (it === drag.li) return;
      var shift = 0;
      if (drag.from < to && i > drag.from && i <= to) shift = -drag.h;
      if (drag.from > to && i < drag.from && i >= to) shift = drag.h;
      it.style.transform = shift ? 'translateY(' + shift + 'px)' : '';
      it.style.transition = 'transform .12s';
    });
    var vh = window.innerHeight;
    if (e.clientY < 80) window.scrollBy(0, -12); else if (e.clientY > vh - 150) window.scrollBy(0, 12);
  }
  function onDragEnd() {
    if (!drag) return;
    var d = drag; drag = null; ui.dragging = false;
    d.items.forEach(function (it) { it.style.transform = ''; it.style.transition = ''; });
    d.li.classList.remove('dragging');
    d.li.removeEventListener('pointermove', onDragMove);
    d.li.removeEventListener('pointerup', onDragEnd);
    d.li.removeEventListener('pointercancel', onDragEnd);
    if (d.to !== d.from && pls()[d.id]) {
      var nt = arr(pls()[d.id].tracks).slice();
      var x = nt.splice(d.from, 1)[0];
      nt.splice(d.to, 0, x);
      optimisticTracks(d.id, nt);
      send('PLAYLIST_UPDATE', { playlist: { id: d.id, tracks: nt } });
    } else render();
  }

  function libraryPickerModal(p) {
    var q = '', sel = {};
    var inPl = {};
    arr(p.tracks).forEach(function (x) { inPl[x] = true; });
    function ids() {
      var c = collator();
      var all = Object.keys(S.db.tracks).filter(function (k) { return !S.db.tracks[k].isUrl; });
      var qq = q.trim().toLowerCase();
      if (qq) all = all.filter(function (k) { var tr = S.db.tracks[k]; return [trackTitle(k), tr.artist, tr.album].join(' ').toLowerCase().indexOf(qq) >= 0; });
      return all.sort(function (a, b) {
        var ta = S.db.tracks[a], tb = S.db.tracks[b];
        return c.compare(ta.album || '', tb.album || '') || c.compare(trackTitle(a), trackTitle(b));
      });
    }
    function count() { return Object.keys(sel).filter(function (k) { return sel[k] && S.db.tracks[k]; }).length; }
    openModal({
      autofocus: 'libq',
      render: function () {
        var list = ids();
        return [h('h3', null, t('from_library') + ' → ' + (p.title || '')),
          h('div', { class: 'search' }, icon('search'), h('input', { class: 'input', 'data-k': 'libq', placeholder: t('search'), value: q,
            oninput: function (e) { q = e.target.value; renderModal(); } })),
          list.length ? h('ul', { class: 'list card', style: 'max-height:50vh;overflow:auto;box-shadow:none;border:1px solid var(--line)' }, list.map(function (k) {
            var tr = S.db.tracks[k];
            return h('li', { class: 'clickable', onclick: function (e) { if (e.target.tagName !== 'INPUT') { sel[k] = !sel[k]; renderModal(); } } },
              h('input', { type: 'checkbox', class: 'check', checked: !!sel[k], 'aria-label': trackTitle(k), onchange: function (e) { sel[k] = e.target.checked; renderModal(); } }),
              h('div', { class: 'grow' }, h('div', { class: 'title ellipsis' }, trackTitle(k)), h('div', { class: 'sub ellipsis' }, trackSub(tr))),
              inPl[k] ? h('span', { class: 'badge' }, t('already_in')) : null);
          })) : h('div', { class: 'empty' }, t('library_empty')),
          h('div', { class: 'foot' }, h('button', { class: 'btn', onclick: closeModal }, t('cancel')),
            h('button', { class: 'btn primary', disabled: !count(), 'data-k': 'libadd', onclick: function () {
              var chosen = Object.keys(sel).filter(function (k) { return sel[k] && S.db.tracks[k]; });
              var cur = pls()[p.id] ? arr(pls()[p.id].tracks) : [];
              var nt = cur.concat(chosen);
              send('PLAYLIST_UPDATE', { playlist: { id: p.id, tracks: nt } });
              closeModal(); toast(t('added', chosen.length));
            } }, count() ? t('add_n', count()) : t('add')))];
      }
    });
  }

  function radioModal(p) {
    var name = '', url = '', err = '';
    function ok() {
      var u = url.trim();
      if (!/^https?:\/\/[\w\[]/i.test(u)) { err = t('radio_url_bad'); renderModal(); return; }
      send('PLAYLIST_ADD_STREAM', { playlistId: p.id, title: name.trim() || u, url: u });
      closeModal();
    }
    openModal({
      autofocus: 'rname',
      render: function () {
        return [h('h3', null, t('radio_title')),
          h('label', { class: 'field' }, h('span', null, t('radio_name')), h('input', { class: 'input', 'data-k': 'rname', value: name, maxlength: '100', oninput: function (e) { name = e.target.value; } })),
          h('label', { class: 'field' }, h('span', null, t('radio_url')), h('input', { class: 'input', 'data-k': 'rurl', type: 'url', inputmode: 'url', value: url, placeholder: 'https://',
            oninput: function (e) { url = e.target.value; }, onkeydown: function (e) { if (e.key === 'Enter') ok(); } })),
          err ? h('div', { class: 'banner danger' }, err) : null,
          h('div', { class: 'foot' }, h('button', { class: 'btn', onclick: closeModal }, t('cancel')), h('button', { class: 'btn primary', onclick: ok }, t('add')))];
      }
    });
  }

  function viewLibrary(tab) {
    tab = tab === 'unused' ? 'unused' : 'all';
    var un = unusedIds();
    var unSet = {}; un.forEach(function (x) { unSet[x] = true; });
    var where = {};
    userPlaylists().forEach(function (p) { arr(p.tracks).forEach(function (x) { (where[x] = where[x] || []).push(p.title || '—'); }); });
    var c = collator();
    var all = Object.keys(S.db.tracks).filter(function (k) { return tab === 'all' || unSet[k]; });
    var qq = ui.search.trim().toLowerCase();
    if (qq) all = all.filter(function (k) { var tr = S.db.tracks[k]; return [trackTitle(k), tr.artist, tr.album].join(' ').toLowerCase().indexOf(qq) >= 0; });
    all.sort(function (a, b) { var ta = S.db.tracks[a], tb = S.db.tracks[b]; return c.compare(ta.album || '', tb.album || '') || c.compare(trackTitle(a), trackTitle(b)); });
    Object.keys(ui.sel).forEach(function (k) { if (all.indexOf(k) < 0) delete ui.sel[k]; });
    var chosen = all.filter(function (k) { return ui.sel[k]; });
    var nAll = Object.keys(S.db.tracks).length;
    var allChosen = all.length > 0 && chosen.length === all.length;
    return [
      h('div', { class: 'tabs', role: 'tablist' },
        h('button', { class: tab === 'all' ? 'on' : '', role: 'tab', 'aria-selected': String(tab === 'all'), onclick: function () { go('#/library'); } }, t('all') + ' (' + nAll + ')'),
        h('button', { class: tab === 'unused' ? 'on' : '', role: 'tab', 'aria-selected': String(tab === 'unused'), onclick: function () { go('#/library/unused'); } }, t('unused') + ' (' + un.length + ')')),
      h('div', { class: 'actions' }, fileButton(t('add_files'), null, false),
        // select / deselect every track currently listed (this tab, after the search filter)
        all.length ? h('button', { class: 'btn', 'data-k': 'selall', 'aria-pressed': String(allChosen), onclick: function () {
          all.forEach(function (k) { ui.sel[k] = !allChosen; }); render();
        } }, allChosen ? t('select_none') : t('select_all')) : null),
      uploadsBlock(null),
      h('div', { class: 'search' }, icon('search'), h('input', { class: 'input', 'data-k': 'libsearch', placeholder: t('search'), value: ui.search,
        oninput: function (e) { ui.search = e.target.value; render(); } })),
      all.length ? h('ul', { class: 'card list' }, all.map(function (k) {
        var tr = S.db.tracks[k];
        var w = where[k];
        return h('li', { class: 'clickable', 'data-track': k, onclick: function (e) { if (e.target.tagName !== 'INPUT') { ui.sel[k] = !ui.sel[k]; render(); } } },
          h('input', { type: 'checkbox', class: 'check', checked: !!ui.sel[k], 'aria-label': trackTitle(k), onchange: function (e) { ui.sel[k] = e.target.checked; render(); } }),
          h('div', { class: 'grow' }, h('div', { class: 'title ellipsis' }, (tr.isUrl ? '📻 ' : '') + trackTitle(k)),
            h('div', { class: 'sub ellipsis' }, trackSub(tr)),
            h('div', { class: 'sub ellipsis' }, w ? t('in_playlists') + w.join(', ') : t('in_none'))));
      })) : h('div', { class: 'card empty' }, tab === 'unused' ? t('unused_empty') : t('library_empty')),
      chosen.length ? h('div', { class: 'card selbar' },
        h('span', { class: 'grow small' }, t('selected', chosen.length)),
        h('button', { class: 'btn primary', onclick: function () { addToPlaylistModal(chosen); } }, t('add_to')),
        tab === 'unused' ? h('button', { class: 'btn danger', onclick: function () {
          confirmBox(t('delete_forever_q', chosen.length), t('delete_forever_text'), t('delete'), true).then(function (ok) {
            if (!ok) return;
            var keep = unusedIds().filter(function (x) { return chosen.indexOf(x) < 0; });
            send('PLAYLIST_UPDATE', { playlist: { id: 'TRASH', tracks: keep } });
            ui.sel = {}; toast(t('deleted'));
          });
        } }, icon('trash'), t('delete_forever')) : null) : null
    ];
  }

  function addToPlaylistModal(ids) {
    var list = userPlaylists();
    openModal({
      render: function () {
        return [h('h3', null, t('choose_playlist')),
          h('ul', { class: 'list card', style: 'box-shadow:none;border:1px solid var(--line)' },
            list.map(function (p) {
              return h('li', { class: 'clickable', 'data-pl': p.id, onclick: function () {
                var cur = arr(pls()[p.id] && pls()[p.id].tracks);
                send('PLAYLIST_UPDATE', { playlist: { id: p.id, tracks: cur.concat(ids) } });
                ui.sel = {}; closeModal(); toast(t('added', ids.length)); render();
              } }, tokVisual(p.star, 'xs'), h('div', { class: 'grow' }, h('div', { class: 'title' }, p.title || '—'), h('div', { class: 'sub' }, t('n_tracks', arr(p.tracks).length))));
            }),
            h('li', { class: 'clickable', onclick: function () { closeModal(); newPlaylistModal(ids); ui.sel = {}; } },
              h('div', { class: 'tok xs none' }, icon('plus')), h('div', { class: 'grow title' }, t('new_playlist')))),
          h('div', { class: 'foot' }, h('button', { class: 'btn', onclick: closeModal }, t('cancel')))];
      }
    });
  }

  var nameDraft = {};
  var tokq = '';   // the Tokens screen's search box
  function normTxt(s) { return String(s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, ''); }
  // characters with a known token (grouped by character), plus those that only have a playlist
  function tokenGroups() {
    var groups = {};
    Object.keys(S.db.tokens).forEach(function (tag) {
      var tk = S.db.tokens[tag];
      if (!tk || !isUserChar(tk.starId)) return;
      (groups[tk.starId] = groups[tk.starId] || []).push(tag);
    });
    var ids = Object.keys(groups).sort(function (a, b) { return charInfo(a).order - charInfo(b).order; });
    var linkedOnly = userPlaylists().filter(function (p) { return p.star && !groups[p.star]; }).map(function (p) { return p.star; });
    return { groups: groups, ids: ids, linkedOnly: linkedOnly };
  }
  // the details of one character (or foreign tag): its playlist, its physical tokens and their names
  function charModal(sid) {
    var foreign = !!foreignUid(sid);
    openModal({
      live: true,
      sig: function () {
        var g = tokenGroups(); var p = playlistOfChar(sid);
        return JSON.stringify([g.groups[sid], p && p.id, S.nfc.tagId, (g.groups[sid] || []).map(function (tag) { return (S.db.tokens[tag] || {}).image || ''; })]);
      },
      render: function () {
        var p = playlistOfChar(sid);
        var tags = (tokenGroups().groups[sid] || []).sort();
        var sel = h('select', { class: 'input', 'aria-label': t('launches') + ' — ' + charName(sid), 'data-char-select': sid, onchange: function (e) {
          var v = e.target.value;
          e.target.blur();
          if (!v) { if (p) send('PLAYLIST_UPDATE', { playlist: { id: p.id, star: false } }); return; }
          var pl = pls()[v]; var other = pl && pl.star && pl.star !== sid ? pl.star : null;
          if (!other) { send('PLAYLIST_UPDATE', { playlist: { id: v, star: sid } }); return; }
          // that playlist is already started by another character: say so before taking it
          confirmBox(t('launches'), t('pl_taken', pl.title || '—', charName(other)), t('save')).then(function (ok) {
            if (ok) send('PLAYLIST_UPDATE', { playlist: { id: v, star: sid } });
            charModal(sid);   // the question replaced the sheet: back to it either way
          });
        } }, h('option', { value: '' }, t('none_dash')), userPlaylists().map(function (x) { return h('option', { value: x.id, selected: p && p.id === x.id ? 'selected' : null }, x.title || '—'); }));
        if (p) sel.value = p.id; else sel.value = '';
        return [
          h('div', { class: 'row', style: 'margin-bottom:8px' }, tokVisual(sid, '', S.nfc.starId === sid),
            h('div', { class: 'grow' }, h('h3', { style: 'margin:0' }, charName(sid)),
              h('div', { class: 'small muted' }, tags.length ? t('n_tokens', tags.length) : t('no_token')))),
          h('p', { class: 'small muted' }, foreign ? t('foreign_hint') : t('tokens_intro')),
          h('label', { class: 'field' }, h('span', null, t('launches')), sel),
          tags.map(function (tag, i) {
            var tk = S.db.tokens[tag] || {};
            var live = S.nfc.tagId === tag;
            var key = 'name-' + tag;
            var val = nameDraft[tag] !== undefined ? nameDraft[tag] : (tk.name || '');
            function commit() {
              if (rendering || modalRendering || nameDraft[tag] === undefined) return;
              var v = nameDraft[tag].trim();
              delete nameDraft[tag];
              if (v !== (tk.name || '')) { send('TOKEN_EDIT', { tagId: tag, name: v }); toast(t('saved')); }
            }
            // a foreign tag is its own character: its name IS the card's title, so the field says so
            return h('div', { class: 'physical', 'data-tag': tag },
              h('span', { class: 'badge' + (live ? ' accent' : '') }, live ? t('on_jooki') : foreign ? t('nfc_tag') : t('token_n', i + 1)),
              h('input', { class: 'input grow', 'data-k': key, value: val, maxlength: '60', placeholder: foreign ? t('tag_name_ph') : t('token_name_ph'), 'aria-label': foreign ? t('tag_name_ph') : t('token_n', i + 1),
                oninput: function (e) { nameDraft[tag] = e.target.value; },
                onblur: commit, onkeydown: function (e) { if (e.key === 'Enter') { e.target.blur(); } } }),
              h('button', { class: 'icon-btn', 'aria-label': t('forget'), title: t('forget'), onclick: function () {
                confirmBox(t('forget_q'), t('forget_text'), t('forget'), true).then(function (ok) { if (ok) send('TOKEN_DELETE', { tagId: tag }); });
              } }, icon('x')));
          }),
          // a tag can carry a picture: taken now, picked from the gallery or a file on a computer
          foreign && tags.length ? h('div', { class: 'row', style: 'gap:8px;margin-top:6px' },
            h('label', { class: 'btn', style: 'cursor:pointer' }, icon('upload'), t('photo_btn'),
              h('input', { type: 'file', accept: 'image/*', 'data-k': 'photo', style: 'display:none', onchange: function (e) {
                var f = e.target.files && e.target.files[0]; if (!f) return;
                closeModal(); tokenImageEditor(tags[0], f);
              } })),
            (S.db.tokens[tags[0]] || {}).image ? h('button', { class: 'btn ghost', 'data-k': 'photo-remove', onclick: function () { send('TOKEN_EDIT', { tagId: tags[0], image: false }); } }, t('photo_remove')) : null) : null,
          h('div', { class: 'foot' }, h('button', { class: 'btn primary', 'data-k': 'charclose', onclick: closeModal }, t('close')))
        ];
      }
    });
  }
  // the Tokens screen: the visuals only, searched by name; the details open on a tap
  function viewTokens() {
    var g = tokenGroups();
    var all = g.ids.concat(g.linkedOnly);
    var q = normTxt(tokq.trim());
    function matches(sid) {
      if (!q) return true;
      var p = playlistOfChar(sid);
      var names = [charName(sid), p && p.title].concat((g.groups[sid] || []).map(function (tag) { return (S.db.tokens[tag] || {}).name; }));
      return names.some(function (n) { return n && normTxt(n).indexOf(q) >= 0; });
    }
    var shown = all.filter(matches);
    function tile(sid) {
      var p = playlistOfChar(sid);
      var known = !!g.groups[sid];
      return h('button', { class: 'charopt' + (known ? '' : ' nojeton'), 'data-char': sid, onclick: function () { charModal(sid); } },
        tokVisual(sid, '', S.nfc.starId === sid),
        h('div', { class: 'title' }, charName(sid)),
        h('div', { class: 'sub' }, p ? (p.title || '—') : t('none_dash')));
    }
    return [
      all.length ? h('div', { class: 'search' }, icon('search'), h('input', { class: 'input', 'data-k': 'tokq', placeholder: t('tok_search_ph'), value: tokq,
        oninput: function (e) { tokq = e.target.value; render(); } })) : null,
      !all.length ? h('div', { class: 'card empty' }, h('div', { class: 'big' }, '🐉'), t('no_tokens'))
        : !shown.length ? h('div', { class: 'card empty' }, t('tok_no_match'))
        : h('div', { class: 'chargrid' }, shown.map(tile)),
      h('p', { class: 'small muted', style: 'text-align:center' }, t('tokens_hint')),
      g.ids.some(foreignUid) ? h('p', { class: 'small muted', style: 'text-align:center' }, t('foreign_hint')) : null
    ];
  }

  /* ------------------------------------------------------------------ a picture for a tag */
  // The whole job happens in the browser: the photo (camera, gallery or a file on a computer) is
  // read into a canvas, the background is removed by flood fill (a tap = a magic wand on that
  // zone, "Remove the background" = the same from the edges), then rotation, zoom and drag frame
  // the object in a circle. The Jooki only receives a 128 px PNG (about 10 KB).
  function uploadBlob(blob, name, cb) {
    var uid = String(Math.floor(Math.random() * 9e6) + 1e6);
    var fd = new FormData(); fd.append(uid, blob, name);
    var xhr = new XMLHttpRequest();
    xhr.open('POST', '/upload'); xhr.timeout = 60000;
    xhr.onerror = xhr.ontimeout = xhr.onabort = function () { cb(null); };
    xhr.onload = function () { cb(xhr.status === 200 ? uid : null); };
    xhr.send(fd);
  }
  function tokenImageEditor(tag, file) {
    var SRC_MAX = 640, VIEW = 320, OUT = 128, R = VIEW / 2 - 6;
    var src = document.createElement('canvas'), cut = document.createElement('canvas'), sw = 0, sh = 0;
    var keep = null, undo = [], rot = 0, zoom = 1, px = 0, py = 0, tol = 30, busy = false;
    var view = h('canvas', { class: 'edcanvas', width: VIEW, height: VIEW, 'aria-label': t('ed_title') });
    var vctx = view.getContext('2d');
    var status = h('div', { class: 'small muted', style: 'min-height:18px' }, t('ed_hint'));
    function fitScale() { return (R * 2) / Math.max(sw, sh); }
    function rebuildCut() {
      var c = cut.getContext('2d'); c.clearRect(0, 0, sw, sh); c.drawImage(src, 0, 0);
      var d = c.getImageData(0, 0, sw, sh), a = d.data;
      for (var i = 0, n = sw * sh; i < n; i++) if (!keep[i]) a[i * 4 + 3] = 0;
      c.putImageData(d, 0, 0);
    }
    function place(ctx, cx, cy, k) {
      ctx.translate(cx + px * k, cy + py * k); ctx.rotate(rot * Math.PI / 180); var s = fitScale() * zoom * k; ctx.scale(s, s); ctx.translate(-sw / 2, -sh / 2);
    }
    function draw() {
      vctx.clearRect(0, 0, VIEW, VIEW);
      vctx.save(); vctx.globalAlpha = 0.25; place(vctx, VIEW / 2, VIEW / 2, 1); vctx.drawImage(cut, 0, 0); vctx.restore();
      vctx.save(); vctx.beginPath(); vctx.arc(VIEW / 2, VIEW / 2, R, 0, Math.PI * 2); vctx.clip(); place(vctx, VIEW / 2, VIEW / 2, 1); vctx.drawImage(cut, 0, 0); vctx.restore();
      vctx.save(); vctx.beginPath(); vctx.arc(VIEW / 2, VIEW / 2, R, 0, Math.PI * 2); vctx.strokeStyle = 'rgba(0,0,0,.35)'; vctx.lineWidth = 2; vctx.stroke(); vctx.restore();
    }
    function toSrc(vx, vy) {   // a point of the view -> a pixel of the source
      var x = vx - VIEW / 2 - px, y = vy - VIEW / 2 - py, a = -rot * Math.PI / 180, s = fitScale() * zoom;
      var rx = x * Math.cos(a) - y * Math.sin(a), ry = x * Math.sin(a) + y * Math.cos(a);
      return [Math.floor(rx / s + sw / 2), Math.floor(ry / s + sh / 2)];
    }
    function pushUndo() { undo.push(keep.slice(0)); if (undo.length > 10) undo.shift(); }
    var ready = function () { return !!keep && !busy; };   // nothing works before the picture is loaded
    function flood(seeds) {   // seeds: [[x, y]]; each zone is compared with the colour under its own seed
      var d = src.getContext('2d').getImageData(0, 0, sw, sh).data, lim = tol * 4.4, changed = false;
      seeds.forEach(function (sd) {
        var x0 = sd[0], y0 = sd[1];
        if (x0 < 0 || y0 < 0 || x0 >= sw || y0 >= sh) return;
        var i0 = (y0 * sw + x0), r0 = d[i0 * 4], g0 = d[i0 * 4 + 1], b0 = d[i0 * 4 + 2];
        if (!keep[i0]) return;
        var stack = [i0], seen = new Uint8Array(sw * sh); seen[i0] = 1;
        while (stack.length) {
          var i = stack.pop(), dr = d[i * 4] - r0, dg = d[i * 4 + 1] - g0, db = d[i * 4 + 2] - b0;
          if (Math.sqrt(dr * dr + dg * dg + db * db) > lim) continue;
          keep[i] = 0; changed = true;
          var x = i % sw, y = (i - x) / sw;
          if (x > 0 && !seen[i - 1]) { seen[i - 1] = 1; stack.push(i - 1); }
          if (x < sw - 1 && !seen[i + 1]) { seen[i + 1] = 1; stack.push(i + 1); }
          if (y > 0 && !seen[i - sw]) { seen[i - sw] = 1; stack.push(i - sw); }
          if (y < sh - 1 && !seen[i + sw]) { seen[i + sw] = 1; stack.push(i + sw); }
        }
      });
      return changed;
    }
    function act(seeds) { if (!ready()) return; pushUndo(); if (flood(seeds)) { rebuildCut(); draw(); } else undo.pop(); }
    function removeBackground() {
      var e = 2, mx = Math.floor(sw / 2), my = Math.floor(sh / 2);
      act([[e, e], [sw - 1 - e, e], [e, sh - 1 - e], [sw - 1 - e, sh - 1 - e], [mx, e], [mx, sh - 1 - e], [e, my], [sw - 1 - e, my]]);
    }
    // pointer: a drag moves the picture, a tap is the wand
    var down = null;
    function pt(e) { var b = view.getBoundingClientRect(); return [(e.clientX - b.left) * VIEW / b.width, (e.clientY - b.top) * VIEW / b.height]; }
    view.addEventListener('pointerdown', function (e) { if (busy) return; view.setPointerCapture(e.pointerId); var p = pt(e); down = { x: p[0], y: p[1], px: px, py: py, moved: false }; e.preventDefault(); });
    view.addEventListener('pointermove', function (e) {
      if (!down) return; var p = pt(e), dx = p[0] - down.x, dy = p[1] - down.y;
      if (Math.abs(dx) + Math.abs(dy) > 6) down.moved = true;
      if (down.moved) { px = down.px + dx; py = down.py + dy; draw(); }
    });
    view.addEventListener('pointerup', function (e) {
      if (!down) return; var d0 = down; down = null;
      if (!d0.moved) { var p = pt(e), s = toSrc(p[0], p[1]); act([s]); }
    });
    view.addEventListener('pointercancel', function () { down = null; });
    function range(key, label, min, max, step, get, set) {
      var out = h('span', { class: 'small muted' });
      var inp = h('input', { type: 'range', class: 'range', 'data-k': key, min: String(min), max: String(max), step: String(step), value: String(get()),
        'aria-label': label, oninput: function (e) { set(parseFloat(e.target.value)); out.textContent = fmt(); draw(); } });
      function fmt() { var v = get(); return key === 'edrot' ? Math.round(v) + '°' : key === 'edzoom' ? '×' + v.toFixed(1) : Math.round(v); }
      out.textContent = fmt();
      return h('label', { class: 'edrow' }, h('span', null, label), inp, out);
    }
    function save() {
      if (!ready()) return; busy = true; status.textContent = t('ed_sending');
      var o = document.createElement('canvas'); o.width = OUT; o.height = OUT; var c = o.getContext('2d');
      c.beginPath(); c.arc(OUT / 2, OUT / 2, OUT / 2, 0, Math.PI * 2); c.clip();
      place(c, OUT / 2, OUT / 2, OUT / (R * 2)); c.drawImage(cut, 0, 0);
      o.toBlob(function (blob) {
        if (!blob) { busy = false; status.textContent = t('photo_fail'); return; }
        uploadBlob(blob, 'tok_' + tag + '.png', function (uploadId) {
          if (!uploadId) { busy = false; status.textContent = t('photo_fail'); return; }
          var before = (S.db.tokens[tag] || {}).image || '';
          send('TOKEN_SET_IMAGE', { tagId: tag, uploadId: uploadId });
          var tries = 0, tm = setInterval(function () {
            var now = (S.db.tokens[tag] || {}).image || '';
            if (now && now !== before) { clearInterval(tm); closeModal(); toast(t('saved')); charModal('tag.' + tag); }
            else if (++tries > 60) { clearInterval(tm); busy = false; status.textContent = t('photo_fail'); }
          }, 250);
        });
      }, 'image/png');
    }
    var body = h('div', null,
      h('h3', null, t('ed_title')),
      h('div', { class: 'edwrap' }, view),
      status,
      h('div', { class: 'edtools' },
        h('button', { class: 'btn', 'data-k': 'edbg', onclick: removeBackground }, t('ed_bg')),
        h('button', { class: 'btn', 'data-k': 'edundo', onclick: function () { if (ready() && undo.length) { keep = undo.pop(); rebuildCut(); draw(); } } }, t('ed_undo')),
        h('button', { class: 'btn', 'data-k': 'edrot90', onclick: function () { if (!ready()) return; rot = (rot + 90) % 360; rotInp.querySelector('input').value = String(rot > 180 ? rot - 360 : rot); draw(); } }, '↻ 90°')),
      range('edtol', t('ed_tol'), 0, 100, 1, function () { return tol; }, function (v) { tol = v; }),
      (function () { rotInp = range('edrot', t('ed_rot'), -180, 180, 1, function () { return rot; }, function (v) { rot = v; }); return rotInp; })(),
      range('edzoom', t('ed_zoom'), 0.5, 4, 0.1, function () { return zoom; }, function (v) { zoom = v; }),
      h('div', { class: 'foot' },
        h('button', { class: 'btn', onclick: function () { closeModal(); charModal('tag.' + tag); } }, t('cancel')),
        h('button', { class: 'btn', 'data-k': 'edreset', onclick: function () { if (!ready()) return; pushUndo(); keep.fill(1); rot = 0; zoom = 1; px = py = 0; rebuildCut(); draw(); } }, t('ed_reset')),
        h('button', { class: 'btn primary', 'data-k': 'edsave', onclick: save }, t('ed_save'))));
    var rotInp;
    openModal({ render: function () { return body; } });
    // read as a data: URL, not a blob: URL: the page's content security policy allows img-src 'self' data:
    var img = new Image(), rd = new FileReader();
    rd.onerror = function () { status.textContent = t('photo_bad'); };
    rd.onload = function () { img.src = rd.result; };
    img.onload = function () {
      var k = Math.min(1, SRC_MAX / Math.max(img.naturalWidth, img.naturalHeight));
      sw = Math.max(1, Math.round(img.naturalWidth * k)); sh = Math.max(1, Math.round(img.naturalHeight * k));
      src.width = cut.width = sw; src.height = cut.height = sh;
      src.getContext('2d').drawImage(img, 0, 0, sw, sh);
      keep = new Uint8Array(sw * sh); keep.fill(1);
      rebuildCut(); draw();
    };
    img.onerror = function () { status.textContent = t('photo_bad'); };
    rd.readAsDataURL(file);
  }

  /* ---------------- OpenJooki updates (the Jooki itself talks to GitHub) */
  var upd = { state: 'idle', latest: null, lines: '', startedFrom: null };
  function vparts(v) { return String(v || '0').split(/[.-]/).map(function (x) { return parseInt(x, 10) || 0; }); }
  function newer(a, b) {
    var x = vparts(a), y = vparts(b);
    for (var i = 0; i < Math.max(x.length, y.length); i++) { if ((x[i] || 0) !== (y[i] || 0)) return (x[i] || 0) > (y[i] || 0); }
    return false;
  }
  function installed() { return S.device.openjooki || null; }
  function updateAvailable() { return upd.latest && installed() && newer(upd.latest, installed()); }
  function getText(path, cb) {
    var x = new XMLHttpRequest();
    x.open('GET', path + (path.indexOf('?') < 0 ? '?' : '&') + 't=' + Date.now());
    x.timeout = 5000;
    x.onload = function () { cb(x.status === 200 ? x.responseText : null, x.getResponseHeader('Last-Modified')); };
    x.onerror = x.ontimeout = function () { cb(null, null); };
    x.send();
  }
  function checkUpdate() {
    if (upd.state === 'running' || upd.state === 'rebooting' || !installed()) return;
    upd.state = 'checking'; render();
    var t0 = Date.now();
    // the Jooki writes {"pending":true} right away, then the answer from GitHub
    send('OJ_UPDATE_CHECK', {});
    setTimeout(function poll() {
      getText('/oj-latest.json', function (txt) {
        var d = null;
        try { d = JSON.parse(txt); } catch (e) {}
        if (d && !d.pending) {
          if (d.error || !d.version) { upd.state = 'offline'; }
          else { upd.latest = String(d.version); upd.state = 'checked'; }
          render(); return;
        }
        if (Date.now() - t0 > 40000) { upd.state = 'offline'; render(); return; }
        setTimeout(poll, 1500);
      });
    }, 1500);
  }
  function startUpdate() {
    confirmBox(t('upd_q', upd.latest), t('upd_text'), t('upd_now'), false).then(function (ok) {
      if (!ok) return;
      upd.state = 'running'; upd.lines = ''; upd.startedFrom = installed(); upd.step = 0; upd.pct = null; upd.reboot = false;
      send('OJ_UPDATE_START', {});
      render();
      setTimeout(function poll() {
        if (upd.state !== 'running') return;
        getText('/oj-status.txt', function (txt) {
          if (txt) {
            upd.lines = txt;
            var p = updProgress(txt);
            upd.step = p.step; upd.pct = p.pct;
            // what the installer wrote before it asked for the reboot: later lines come from a dying process
            var before = txt.split('REBOOT_NOW')[0];
            if (/already up to date/i.test(txt)) { upd.state = 'checked'; toast(t('upd_uptodate')); render(); return; }
            if (!p.reboot && /ERROR|SAFETY|INVALID|not performed|did not complete|download failed|no network|invalid manifest/i.test(before) && !/retry/i.test(before.split('\n').filter(Boolean).pop() || '')) {
              upd.state = 'failed'; render(); return;
            }
            upd.reboot = p.reboot;
          }
          render();
          setTimeout(poll, 3000);
        });
      }, 1500);
    });
  }
  // The installer's report (oj-status.txt, its own words and curl's meter) -> which step, how far.
  // Steps: 0 looking, 1 downloading, 2 checking the download, 3 installing, 4 checking the install, 5 restarting.
  function updProgress(txt) {
    var step = 0, pct = null, lines = txt.split(/[\r\n]+/), dl = false;
    for (var i = 0; i < lines.length; i++) {
      var l = lines[i];
      if (/downloading/i.test(l)) { step = Math.max(step, 1); dl = true; }
      else if (/verifying sha256|image intact/i.test(l)) { step = Math.max(step, 2); dl = false; }
      else if (/A\/B install|writing to spare/i.test(l)) { step = Math.max(step, 3); dl = false; }
      else if (/bit-for-bit|bit-perfect/i.test(l)) step = Math.max(step, 4);
      else if (/arming|commit-on-boot|REBOOT_NOW/i.test(l)) step = Math.max(step, 5);
      var m = dl && /^\s*(\d{1,3})\s+\d+(\.\d+)?[kMG]?\s+\d{1,3}\s/.exec(l);   // curl: "  8 40.0M  8 3293k ..."
      if (m) pct = Math.min(100, +m[1]);
    }
    return { step: step, pct: step === 1 ? pct : null, reboot: /REBOOT_NOW/.test(txt) };
  }
  function updSteps() {
    var names = t('upd_steps'), cur = upd.state === 'rebooting' ? 5 : (upd.step || 0);
    return h('ol', { class: 'updsteps' }, names.map(function (n, i) {
      var done = i < cur, now = i === cur;
      return h('li', { class: done ? 'done' : now ? 'now' : '' }, h('span', { class: 'mark' }, done ? '✓' : now ? '•' : ''),
        h('span', null, n + (now && i === 1 && upd.pct !== null ? ' … ' + upd.pct + ' %' : now ? '…' : '')));
    }));
  }
  function updateCard() {
    var cur = installed();
    var status = null, action = null;
    if (upd.state === 'checking') status = t('upd_checking');
    else if (upd.state === 'offline') status = t('upd_offline');
    else if (upd.state === 'failed') status = t('upd_failed');
    else if (upd.state === 'checked') status = updateAvailable() ? t('upd_available', upd.latest) : t('upd_uptodate');
    if (upd.state === 'running' || upd.state === 'rebooting') {
      return h('div', { class: 'card', style: 'padding:16px', 'data-k': 'updcard' },
        h('div', { class: 'row' }, h('div', { class: 'spinner', style: 'width:28px;height:28px;border-width:3px;margin:0' }),
          h('b', { class: 'grow' }, upd.state === 'rebooting' ? t('upd_rebooting') : t('upd_running'))),
        updSteps(),
        h('p', { class: 'small muted' }, t('upd_keep')));
    }
    if (upd.state === 'checked' && updateAvailable()) action = h('button', { class: 'btn primary block', 'data-k': 'updnow', onclick: startUpdate }, icon('upload'), t('upd_now'));
    else action = h('button', { class: 'btn block', 'data-k': 'updcheck', disabled: upd.state === 'checking' || !cur, onclick: checkUpdate }, t('upd_check'));
    return h('div', { class: 'card', style: 'padding:14px 16px' },
      status ? h('p', { class: 'small', style: 'margin:0 0 10px' + (updateAvailable() ? ';color:var(--accent);font-weight:700' : '') }, status) : null, action);
  }
  var lastOnline = true, backAt = 0;
  function watchUpdateReconnect() {
    // only once the installer has asked for the reboot: before that, a lost connection (a busy Jooki,
    // a hiccup of the Wi-Fi) is not a restart, and the report is simply read again when it comes back
    if (upd.state === 'running' && !online && lastOnline && upd.reboot) upd.state = 'rebooting';
    var busy = upd.state === 'running' || upd.state === 'rebooting';
    // back with the new version: done, whether or not we saw the "restarting" line (read every 3 s)
    if (busy && online && gotState && installed() && installed() !== upd.startedFrom) {
      upd.state = 'checked'; toast(t('upd_done', installed())); upd.latest = installed(); backAt = 0;
    }
    // back with the old version after an announced restart: the Jooki went back on its own
    if (upd.state === 'rebooting' && online && gotState && installed()) {
      if (!backAt) {
        backAt = Date.now();
        setTimeout(function () { if (upd.state === 'rebooting' && installed() === upd.startedFrom) { upd.state = 'failed'; render(); } }, 90000);
      }
    }
    lastOnline = online;
  }

  function viewSettings() {
    var d = S.device, pw = S.power, w = S.wifi, cfg = S.audio.config;
    var lvl = pw.level && typeof pw.level === 'object' ? Number(pw.level.p) : NaN;
    var bat = isNaN(lvl) || (lvl === 0 && pw.level && !pw.level.mv) ? '—' : Math.round(lvl / 10) + ' %' + (pw.charging ? ' · ' + t('charging') : pw.connected ? ' · ' + t('plugged') : '');
    var du = obj(d.diskUsage);
    var total = Number(du.total) * 1024, used = Number(du.used) * 1024, free = Number(du.available) * 1024;
    return [
      h('div', { class: 'section-title' }, t('device')),
      h('div', { class: 'card' },
        h('div', { class: 'kv' }, h('span', null, t('device_name')), h('span', { class: 'row' }, h('b', null, (d.hostname || '—').replace(/\.local$/, '')),
          d.core ? h('button', { class: 'btn ghost', 'data-k': 'rename', onclick: nameModal }, t('rename')) : null)),
        h('div', { class: 'kv' }, h('span', null, t('battery')), h('b', null, bat)),
        wifiRow(w),
        h('div', { class: 'kv' }, h('span', null, t('ip')), h('b', null, (d.ip || location.hostname) + (S.net.name ? ' · ' + S.net.name : ''))),
        h('div', { class: 'kv' }, h('span', null, t('storage')), h('b', null, total ? fmtBytes(free) + ' ' + t('free') + ' / ' + fmtBytes(total) : '—')),
        total ? h('div', { class: 'meter' }, h('i', { style: 'width:' + Math.min(100, Math.round(used / total * 100)) + '%' })) : null,
        h('div', { class: 'kv' }, h('span', null, t('version')), h('b', null, 'OpenJooki ' + (d.openjooki || '—'),
          h('div', { class: 'small muted', style: 'font-weight:400' }, t('web_page') + ' ' + VERSION + (d.firmware ? ' · ' + d.firmware : ''))))),
      updateCard(),
      h('div', { class: 'section-title' }, t('playback')),
      h('div', { class: 'card' },
        h('label', { class: 'switch' }, h('span', null, t('toy_safe')), h('input', { type: 'checkbox', role: 'switch', checked: !!d.toy_safe, 'data-k': 'toysafe',
          onchange: function (e) { send('SET_TOY_SAFE', { enable: e.target.checked }); } })),
        h('label', { class: 'switch' }, h('span', null, t('shuffle')), h('input', { type: 'checkbox', role: 'switch', checked: !!cfg.shuffle_mode, 'data-k': 'shuffle',
          onchange: function (e) { send('SET_CFG', { shuffle_mode: e.target.checked }); } })),
        h('label', { class: 'switch' }, h('span', null, t('repeat')), h('input', { type: 'checkbox', role: 'switch', checked: cfg.repeat_mode === 1 || cfg.repeat_mode === true, 'data-k': 'repeat',
          onchange: function (e) { send('SET_CFG', { repeat_mode: e.target.checked ? 1 : 0 }); } }))),
      bedtimeCard(),
      h('div', { class: 'section-title' }, t('language')),
      h('div', { class: 'card', style: 'padding:12px 16px' }, h('div', { class: 'seg', role: 'group', 'aria-label': t('language') },
        LANGS.map(function (l) { return h('button', { class: lang === l[0] ? 'on' : '', lang: l[0], onclick: function () { setLang(l[0]); } }, l[1]); }))),
      securityCard(),
      h('div', { class: 'actions', style: 'margin-top:24px' }, h('button', { class: 'btn danger', onclick: function () {
        confirmBox(t('power_off_q'), t('power_off_text'), t('power_off'), true).then(function (ok) {
          if (!ok) return;
          send('SHUTDOWN', { src: 'from-web' }); toast(t('power_off_done'));
        });
      } }, icon('power'), t('power_off')))
    ];
  }
  // Security switches (docs/adr/0007): only shown on a core that offers them.
  function securityCard() {
    var m = obj(S.maintenance);
    if (typeof m.ssh !== 'boolean' && typeof m.parent !== 'boolean') return null;
    var rows = [
      h('label', { class: 'switch' }, h('span', null, t('ssh_label'), h('div', { class: 'small muted', style: 'font-weight:400' }, t('ssh_help'))),
        h('input', { type: 'checkbox', role: 'switch', checked: !!m.ssh, 'data-k': 'ssh',
          onchange: function (e) { send(e.target.checked ? 'OJ_SSH_ON' : 'OJ_SSH_OFF', {}); } })),
      h('label', { class: 'switch' }, h('span', null, t('mqtt_label'), h('div', { class: 'small muted', style: 'font-weight:400' }, t('mqtt_help'))),
        h('input', { type: 'checkbox', role: 'switch', checked: !!m.mqtt_lan, 'data-k': 'mqttlan',
          onchange: function (e) { send('OJ_MQTT_LAN', { on: e.target.checked }); } }))
    ];
    if (m.mqtt_lan) {
      var host = (S.net && S.net.name ? String(S.net.name).replace(/\.local$/, '.local') : null) || (S.device && S.device.hostname) || location.hostname;
      rows.push(h('div', { class: 'kv' }, h('span', null, t('mqtt_host_l')), h('b', null, host)));
      rows.push(h('div', { class: 'kv' }, h('span', null, t('mqtt_port_l')), h('b', null, '1883')));
      rows.push(h('div', { class: 'kv' }, h('span', null, t('mqtt_user_l')), h('b', null, 'jooki')));
      rows.push(h('div', { class: 'kv' }, h('span', null, t('mqtt_pass_l')), h('b', { style: 'user-select:all;word-break:break-all' }, CFG.mqttPass || '—')));
    }
    rows.push(h('label', { class: 'switch' }, h('span', null, t('parent_label'), h('div', { class: 'small muted', style: 'font-weight:400' }, t('parent_help'))),
      h('input', { type: 'checkbox', role: 'switch', checked: !!m.parent, 'data-k': 'parent',
        onchange: function (e) { e.target.checked = !!m.parent; parentModal(m.parent ? 'off' : 'set'); } })));
    if (m.parent) {
      rows.push(h('div', { class: 'row', style: 'gap:8px;flex-wrap:wrap;margin-top:4px' },
        h('button', { class: 'btn ghost', 'data-k': 'pchange', onclick: function () { parentModal('change'); } }, t('parent_change'))));
      rows.push(h('p', { class: 'small muted' }, t('parent_reset')));
    }
    return [h('div', { class: 'section-title' }, t('sec_title')), h('div', { class: 'card' }, rows)];
  }
  // Ask for the parent code when the Jooki refuses a protected action, then retry it.
  function askParent(bad) {
    var code = '';
    function go() { if (!/^\d{4}$/.test(code)) return; parentCode = code; lsSet('oj.parent', code); closeModal();
      if (pendingCmd) { var pc = pendingCmd; pc.payload.code = code; send(pc.type, pc.payload); } }
    openModal({ autofocus: 'pask', render: function () {
      return [h('h3', null, t('parent_prompt')),
        h('label', { class: 'field' }, h('span', null, t('parent_label')),
          h('input', { class: 'input', 'data-k': 'pask', inputmode: 'numeric', maxlength: '4', value: code, autocomplete: 'off',
            oninput: function (e) { code = e.target.value.replace(/\D/g, ''); }, onkeydown: function (e) { if (e.key === 'Enter') go(); } })),
        bad ? h('p', { class: 'small accent-text' }, t('parent_bad')) : null,
        h('p', { class: 'small muted' }, t('parent_reset')),
        h('div', { class: 'foot' }, h('button', { class: 'btn', onclick: closeModal }, t('cancel')),
          h('button', { class: 'btn primary', onclick: go }, t('save')))];
    } });
  }
  // Set, change or turn off the parent code.
  function parentModal(mode) {
    var cur = '', neu = '', bad = false;
    function submit() {
      if (mode === 'off') {
        if (!/^\d{4}$/.test(cur)) { bad = true; renderModal(); return; }
        send('OJ_PARENT_CLEAR', { current: cur }); closeModal(); return;
      }
      if (!/^\d{4}$/.test(neu) || (mode === 'change' && !/^\d{4}$/.test(cur))) { bad = true; renderModal(); return; }
      send('OJ_PARENT_SET', mode === 'change' ? { code: neu, current: cur } : { code: neu });
      parentCode = neu; lsSet('oj.parent', neu); closeModal();
    }
    openModal({ autofocus: (mode === 'set') ? 'pnew' : 'pcur', render: function () {
      var rows = [h('h3', null, t('parent_label'))];
      if (mode !== 'set') rows.push(h('label', { class: 'field' }, h('span', null, t('parent_cur')),
        h('input', { class: 'input', 'data-k': 'pcur', inputmode: 'numeric', maxlength: '4', value: cur, autocomplete: 'off',
          oninput: function (e) { cur = e.target.value.replace(/\D/g, ''); }, onkeydown: function (e) { if (e.key === 'Enter') submit(); } })));
      if (mode !== 'off') rows.push(h('label', { class: 'field' }, h('span', null, t('parent_new')),
        h('input', { class: 'input', 'data-k': 'pnew', inputmode: 'numeric', maxlength: '4', value: neu, autocomplete: 'off',
          oninput: function (e) { neu = e.target.value.replace(/\D/g, ''); }, onkeydown: function (e) { if (e.key === 'Enter') submit(); } })));
      if (bad) rows.push(h('p', { class: 'small accent-text' }, t('parent_bad')));
      rows.push(h('div', { class: 'foot' }, h('button', { class: 'btn', onclick: closeModal }, t('cancel')),
        h('button', { class: 'btn primary', onclick: submit }, t('save'))));
      return rows;
    } });
  }
  // The Jooki's network name (2.0 core only). The Jooki's web server answers only to its own name,
  // so after a rename the page lives at the new address and the old one stops answering.
  function nameModal() {
    var d = S.device, factory = String(d.id || '').toLowerCase();
    var cur = String(d.hostname || '').replace(/\.local$/, '').toLowerCase();
    var name = cur === factory ? '' : cur, bad = false;
    function valid(v) { return v === '' || (v.length <= 32 && v !== 'localhost' && /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/.test(v)); }
    function save() {
      var v = name.trim().toLowerCase().replace(/\.local$/, '');
      if (!valid(v)) { bad = true; renderModal(); return; }
      var eff = v || factory, url = 'http://' + eff + '.local/';
      closeModal();
      if (eff === cur) return;
      send('OJ_SET_NAME', { name: v });
      confirmBox(t('name_done', eff), t('name_text', url), t('name_open'), false).then(function (ok) { if (ok) location.href = url; });
    }
    openModal({
      autofocus: 'devname',
      render: function () {
        return [h('h3', null, t('name_title')),
          h('label', { class: 'field' }, h('span', null, t('device_name')),
            h('input', { class: 'input', 'data-k': 'devname', maxlength: '40', placeholder: factory, value: name, autocapitalize: 'none', autocorrect: 'off', spellcheck: 'false',
              oninput: function (e) { name = e.target.value; if (bad) { bad = false; renderModal(); } },
              onkeydown: function (e) { if (e.key === 'Enter') save(); } })),
          h('p', { class: 'small ' + (bad ? 'accent-text' : 'muted') }, bad ? t('name_invalid') : t('name_help', factory)),
          h('div', { class: 'foot' }, h('button', { class: 'btn', onclick: closeModal }, t('cancel')),
            h('button', { class: 'btn primary', 'data-k': 'namesave', onclick: save }, t('save')))];
      }
    });
  }
  function wifiRow(w) {
    var dbm = Number(w.signal);
    var has = w.signal !== undefined && w.signal !== null && !isNaN(dbm);
    var q = !has ? null : dbm >= -65 ? 'good' : dbm >= -75 ? 'fair' : 'weak';
    var n = S.net, drops = Number(n.drops) || 0;
    return h('div', { class: 'kv col', 'data-k': 'wifirow' },
      h('div', { class: 'row', style: 'width:100%' }, h('span', { class: 'grow' }, t('wifi')),
        h('b', null, (w.ssid || '—') + (has ? ' · ' + dbm + ' dBm' : ''))),
      q ? h('div', { class: 'small wifi-' + q, 'data-k': 'wifiq' }, t('wifi_' + q) + (drops ? ' · ' + t('wifi_drops', drops) : '')) : null,
      q === 'weak' ? h('div', { class: 'small muted' }, t('wifi_advice')) : null);
  }
  function setLang(l) { lang = l; lsSet('oj.lang', l); document.documentElement.lang = l; render(); }

  /* ------------------------------------------------------------------ bedtime */
  function sleepInfo() { var s = S.bedtime.sleep; return s && typeof s === 'object' && s.mode ? s : null; }
  function sleepLeft() {
    var s = sleepInfo();
    if (!s || s.remaining === undefined || s.remaining === null) return null;
    return Math.max(0, Number(s.remaining) - (Date.now() - sleepStamp) / 1000);
  }
  function sleepText() {
    var s = sleepInfo();
    if (!s) return t('sleep_timer');
    return (s.mode === 'track' ? t('sleep_at_end') : t('sleep_left', fmtTime(sleepLeft()))) + (s.auto ? ' · ' + t('sleep_auto') : '');
  }
  function sleepShort() { var s = sleepInfo(); return !s ? '' : s.mode === 'track' ? t('sleep_track') : fmtTime(sleepLeft()); }
  function hm(m) { m = Number(m) || 0; var hh = Math.floor(m / 60) % 24, mm = m % 60; return (hh < 10 ? '0' : '') + hh + ':' + (mm < 10 ? '0' : '') + mm; }
  // the Jooki keeps UTC: tell it the family's time zone (Europe: summer time rule handled on the Jooki)
  function browserClock() {
    var y = new Date().getFullYear();
    var jan = new Date(y, 0, 1).getTimezoneOffset(), jul = new Date(y, 6, 1).getTimezoneOffset();
    var zone = '';
    try { zone = Intl.DateTimeFormat().resolvedOptions().timeZone || ''; } catch (e) {}
    if (jan !== jul && /^Europe\//.test(zone)) return { tzbase: -Math.max(jan, jul), tzdst: 'EU' };
    return { tzbase: -new Date().getTimezoneOffset(), tzdst: 'none' };
  }
  var clockSynced = false;
  function syncClock() {
    var c = S.bedtime.cfg;
    if (clockSynced || c.tzbase === undefined || !online) return;
    clockSynced = true;
    var b = browserClock();
    if (b.tzbase !== c.tzbase || b.tzdst !== c.tzdst) send('OJ_BEDTIME_SET', b);
  }
  function setBedtime(p) { var b = browserClock(); p.tzbase = b.tzbase; p.tzdst = b.tzdst; send('OJ_BEDTIME_SET', p); }
  function sleepPanel() {
    var s = sleepInfo();
    return h('div', { class: 'sleep' },
      h('div', { class: 'row small muted sleephead' }, icon('moon'), h('span', { 'data-sleep': '1' }, sleepText())),
      h('div', { class: 'chips' },
        [10, 20, 30, 45, 60].map(function (m) {
          return h('button', { class: 'toggle', 'data-sleep-min': String(m), onclick: function () { send('OJ_SLEEP', { minutes: m }); } }, t('sleep_min', m));
        }),
        h('button', { class: 'toggle' + (s && s.mode === 'track' ? ' on' : ''), 'data-sleep-min': 'track', onclick: function () { send('OJ_SLEEP', { mode: 'track' }); } }, t('sleep_track')),
        s ? h('button', { class: 'toggle', 'data-k': 'sleepoff', 'aria-label': t('sleep_cancel'), onclick: function () { send('OJ_SLEEP', { cancel: true }); } }, icon('x'), t('sleep_off')) : null));
  }
  var nightVolDrag = null;
  function bedtimeCard() {
    var c = S.bedtime.cfg;
    if (c.start === undefined) return null; // firmware without bedtime
    var mv = nightVolDrag !== null ? nightVolDrag : Number(c.maxvol) || 100;
    var timers = [0, 10, 15, 20, 30, 45, 60];
    if (timers.indexOf(Number(c.timer)) < 0) { timers.push(Number(c.timer)); timers.sort(function (a, b) { return a - b; }); }
    function volLabel(v) { return t('night_maxvol') + ' : ' + (v >= 100 ? t('night_nolimit') : v + ' %'); }
    return [h('div', { class: 'section-title' }, t('bedtime')),
      h('div', { class: 'card', 'data-k': 'bedcard' },
        h('label', { class: 'switch' }, h('div', null, h('div', null, t('night_mode')), h('div', { class: 'small muted' }, t('night_help'))),
          h('input', { type: 'checkbox', role: 'switch', checked: !!c.enabled, 'data-k': 'nighton', onchange: function (e) { setBedtime({ enabled: e.target.checked }); } })),
        c.enabled ? [
          h('div', { class: 'kv', 'data-k': 'nightstatus' }, S.bedtime.night ? h('b', { class: 'accent-text' }, t('night_now')) : h('span', { class: 'muted' }, t('night_next', hm(c.start)))),
          h('div', { class: 'timepair' },
            h('label', { class: 'field' }, h('span', null, t('night_from')), h('input', { class: 'input', type: 'time', value: hm(c.start), 'data-k': 'nightstart',
              onchange: function (e) { if (e.target.value) setBedtime({ start: e.target.value }); } })),
            h('label', { class: 'field' }, h('span', null, t('night_to')), h('input', { class: 'input', type: 'time', value: hm(c.stop), 'data-k': 'nightstop',
              onchange: function (e) { if (e.target.value) setBedtime({ stop: e.target.value }); } }))),
          h('label', { class: 'field pad' }, h('span', null, t('night_timer')),
            h('select', { class: 'input', 'data-k': 'nighttimer', onchange: function (e) { e.target.blur(); setBedtime({ timer: Number(e.target.value) }); } },
              timers.map(function (m) { return h('option', { value: String(m), selected: Number(c.timer) === m ? 'selected' : null }, m ? t('sleep_min', m) : t('night_timer_none')); }))),
          h('label', { class: 'field pad' }, h('span', { 'data-nightvol': '1' }, volLabel(mv)),
            h('input', { class: 'range', type: 'range', min: '10', max: '100', step: '5', value: String(mv), 'data-k': 'nightvol',
              oninput: function (e) { nightVolDrag = Number(e.target.value); var l = document.querySelector('[data-nightvol]'); if (l) l.textContent = volLabel(nightVolDrag); },
              onchange: function (e) { nightVolDrag = null; setBedtime({ maxvol: Number(e.target.value) }); } })),
          h('label', { class: 'switch' }, h('span', null, t('night_dim')), h('input', { type: 'checkbox', role: 'switch', checked: !!c.dim, 'data-k': 'nightdim',
            onchange: function (e) { setBedtime({ dim: e.target.checked }); } })),
          h('p', { class: 'small muted pad', style: 'margin:4px 0 14px' }, t('night_clock'))
        ] : null)];
  }
  /* sort a playlist by one criterion; web radios keep their relative order at the end */
  var SORT_KEYS = ['name', 'title', 'artist', 'album', 'duration'];
  function fileName(tr) {
    var f = tr.userFilename || String(tr.filename || '').split('/').pop();
    return cleanTitle(f || tr.title || '');
  }
  function sortedTracks(list, by, desc) {
    var c = collator();
    function txt(id, k) {
      var tr = S.db.tracks[id] || {};
      if (k === 'name') return fileName(tr);
      if (k === 'title') return trackTitle(id);
      var v = tr[k]; return v && v !== 'unknown' ? String(v) : '';
    }
    function cmp(a, b) {
      var r;
      if (by === 'duration') r = (Number((S.db.tracks[a] || {}).duration) || 0) - (Number((S.db.tracks[b] || {}).duration) || 0);
      else r = c.compare(txt(a, by), txt(b, by));
      if (r === 0 && by !== 'title') r = c.compare(trackTitle(a), trackTitle(b));
      return r || (a < b ? -1 : a > b ? 1 : 0);
    }
    var files = list.filter(function (x) { return !(S.db.tracks[x] || {}).isUrl; }).sort(cmp);
    if (desc) files.reverse();
    return files.concat(list.filter(function (x) { return (S.db.tracks[x] || {}).isUrl; }));
  }
  function sortModal(p) {
    var by = 'name', desc = false;
    var cur = arr(p.tracks);
    function result() { return sortedTracks(cur, by, desc); }
    function apply() {
      var nt = result();
      closeModal();
      if (nt.join('|') === cur.join('|')) { toast(t('sort_same')); return; }
      optimisticTracks(p.id, nt);
      send('PLAYLIST_UPDATE', { playlist: { id: p.id, tracks: nt } });
      toast(t('sorted'));
    }
    openModal({
      autofocus: 'sortok',
      render: function () {
        var nt = result(), same = nt.join('|') === cur.join('|');
        var shown = nt.slice(0, 8);
        return [h('h3', null, t('sort_title')),
          h('div', { class: 'sortopts', role: 'group', 'aria-label': t('sort_title') }, SORT_KEYS.map(function (k) {
            var on = by === k;
            return h('button', { class: 'btn' + (on ? ' on' : ''), 'data-k': 'sortby-' + k, 'aria-pressed': String(on), onclick: function () {
              if (on) desc = !desc; else { by = k; desc = false; }
              renderModal();
            } }, h('span', { class: 'grow' }, t('sort_by_' + k)), h('span', { 'aria-hidden': 'true' }, on ? (desc ? '↓' : '↑') : ''));
          })),
          h('p', { class: 'small muted' }, t('sort_again')),
          h('div', { class: 'small muted', style: 'margin-top:10px' }, t('sort_preview')),
          h('ol', { class: 'sortpreview' }, shown.map(function (id) { var tr = S.db.tracks[id] || {}; return h('li', { class: 'ellipsis' }, (by === 'name' ? fileName(tr) : trackTitle(id)) + (by === 'duration' && tr.duration ? ' · ' + fmtTime(tr.duration) : '')); }),
            nt.length > shown.length ? h('li', { class: 'muted' }, '… +' + (nt.length - shown.length)) : null),
          h('div', { class: 'foot' }, h('button', { class: 'btn', onclick: closeModal }, t('cancel')),
            h('button', { class: 'btn primary', 'data-k': 'sortok', disabled: same ? 'disabled' : null, onclick: apply }, same ? t('sort_same') : t('sort_apply')))];
      }
    });
  }

  /* ------------------------------------------------------------------ player */
  function isPlaying() { return S.audio.playback.state === 'PLAYING' || S.audio.playback.state === 'STARTING'; }
  function hasNow() { var np = S.audio.nowPlaying; return !!(np && np.playlistId && np.uri); }
  function curPos() {
    var pb = S.audio.playback;
    var p = Number(pb.position_ms) || 0;
    if (pb.state === 'PLAYING') p += Date.now() - posStamp;
    var d = Number(S.audio.nowPlaying.duration_ms) || 0;
    return d ? Math.min(p, d) : p;
  }
  function playerBar() {
    var np = S.audio.nowPlaying;
    var pl = pls()[np.playlistId];
    var now = hasNow();
    var cover = h('div', { class: 'cover' });
    var fallback = function () { return now && pl && pl.star ? tokVisual(pl.star, 'sm') : icon('note'); };
    if (now && np.image) {
      var ci = h('img', { src: np.image, alt: '' });
      ci.onerror = function () { ci.replaceWith(fallback()); };
      cover.appendChild(ci);
    } else cover.appendChild(fallback());
    var d = Number(np.duration_ms) || 0;
    return h('div', { class: 'player' + (now ? '' : ' idle'), 'data-k': 'player' },
      h('div', { class: 'prog' }, h('i', { 'data-prog': '1', style: 'width:' + (d ? Math.round(curPos() / d * 100) : 0) + '%' })),
      cover,
      h('div', { class: 'info', role: 'button', tabindex: '0', 'aria-label': t('open_player'), onclick: function () { if (now) nowPlayingModal(); },
        onkeydown: function (e) { if (e.key === 'Enter' && now) nowPlayingModal(); } },
        h('div', { class: 't ellipsis' }, now ? cleanTitle(np.track || trackTitle(np.trackId)) : t('nothing_playing')),
        h('div', { class: 's ellipsis' }, sleepInfo() ? h('span', { class: 'sleepmini' }, icon('moon'), h('span', { 'data-sleep-short': '1' }, sleepShort())) : null,
          now ? (np.source || (pl && pl.title) || '') : t('nothing_hint'))),
      now ? h('button', { class: 'icon-btn', 'aria-label': t('prev'), onclick: function () { send('DO_PREV', {}); } }, icon('prev')) : null,
      now ? h('button', { class: 'icon-btn accent', 'aria-label': isPlaying() ? t('pause') : t('play'), 'data-k': 'pp',
        onclick: function () { send(isPlaying() ? 'DO_PAUSE' : 'DO_PLAY', {}); } }, icon(isPlaying() ? 'pause' : 'play')) : null,
      now ? h('button', { class: 'icon-btn', 'aria-label': t('next'), onclick: function () { send('DO_NEXT', {}); } }, icon('next')) : null);
  }
  var seeking = false, volDrag = null;
  function nowPlayingModal() {
    openModal({
      live: true,
      sig: function () {
        var np = S.audio.nowPlaying, c = S.audio.config;
        var sl = sleepInfo() || {};
        return [np.playlistId, np.trackId, np.trackIndex, S.audio.playback.state, c.volume, c.shuffle_mode, c.repeat_mode, np.duration_ms, sl.mode, sl.total, sl.auto].join('|');
      },
      render: function () {
        var np = S.audio.nowPlaying, pl = pls()[np.playlistId];
        var cfg = S.audio.config;
        var d = Number(np.duration_ms) || 0;
        var stream = np.service === 'STREAM';
        var art = h('div', { class: 'art' });
        if (np.image) {
          var ai = h('img', { src: np.image, alt: '' });
          ai.onerror = function () { ai.replaceWith(tokVisual(pl && pl.star, '')); };
          art.appendChild(ai);
        } else art.appendChild(tokVisual(pl && pl.star, ''));
        var vol = volDrag !== null ? volDrag : Number(cfg.volume) || 0;
        return h('div', { class: 'np' }, art,
          h('div', { class: 't' }, cleanTitle(np.track || trackTitle(np.trackId)) || '—'),
          h('div', { class: 'muted' }, [np.artist && np.artist !== 'unknown' ? np.artist : null, np.source || (pl && pl.title)].filter(Boolean).join(' · ')),
          stream ? h('div', { class: 'badge accent', style: 'margin-top:12px' }, t('live')) : [
            h('input', { class: 'range', type: 'range', min: '0', max: String(d || 1), value: String(Math.round(curPos())), 'aria-label': 'position', 'data-k': 'seek', 'data-seek': '1',
              oninput: function () { seeking = true; }, onchange: function (e) { seeking = false; send('SEEK', { position_ms: Math.max(1, Number(e.target.value)) }); } }),
            h('div', { class: 'times' }, h('span', { 'data-cur': '1' }, fmtTime(curPos() / 1000)), h('span', null, fmtTime(d / 1000)))],
          h('div', { class: 'controls' },
            h('button', { class: 'icon-btn', 'aria-label': t('prev'), onclick: function () { send('DO_PREV', {}); } }, icon('prev')),
            h('button', { class: 'icon-btn accent', 'aria-label': isPlaying() ? t('pause') : t('play'), 'data-k': 'nppp', onclick: function () { send(isPlaying() ? 'DO_PAUSE' : 'DO_PLAY', {}); } }, icon(isPlaying() ? 'pause' : 'play')),
            h('button', { class: 'icon-btn', 'aria-label': t('next'), onclick: function () { send('DO_NEXT', {}); } }, icon('next'))),
          h('div', { class: 'vol' }, icon('vol'), h('input', { class: 'range', type: 'range', min: '0', max: '100', step: '5', value: String(vol), 'aria-label': t('volume'), 'data-k': 'vol',
            oninput: function (e) { volDrag = Number(e.target.value); }, onchange: function (e) { volDrag = null; send('SET_VOL', { vol: Number(e.target.value) }); } })),
          h('div', { class: 'toggles' },
            h('button', { class: 'toggle' + (cfg.shuffle_mode ? ' on' : ''), 'aria-pressed': String(!!cfg.shuffle_mode), onclick: function () { send('SET_CFG', { shuffle_mode: !cfg.shuffle_mode }); } }, icon('shuffle'), t('shuffle')),
            h('button', { class: 'toggle' + (cfg.repeat_mode === 1 ? ' on' : ''), 'aria-pressed': String(cfg.repeat_mode === 1), onclick: function () { send('SET_CFG', { repeat_mode: cfg.repeat_mode === 1 ? 0 : 1 }); } }, icon('repeat'), t('repeat'))),
          S.bedtime.cfg.start !== undefined ? sleepPanel() : null,
          h('div', { class: 'foot' }, h('button', { class: 'btn block', onclick: closeModal }, t('close'))));
      }
    });
  }
  setInterval(function () {
    if (sleepInfo()) {
      Array.prototype.forEach.call(document.querySelectorAll('[data-sleep]'), function (el) { el.textContent = sleepText(); });
      Array.prototype.forEach.call(document.querySelectorAll('[data-sleep-short]'), function (el) { el.textContent = sleepShort(); });
    }
    if (!hasNow() || S.audio.playback.state !== 'PLAYING') return;
    var d = Number(S.audio.nowPlaying.duration_ms) || 0;
    var p = curPos();
    var bar = document.querySelector('[data-prog]');
    if (bar && d) bar.style.width = Math.round(p / d * 100) + '%';
    if (!seeking) {
      var r = document.querySelector('[data-seek]'); if (r) r.value = String(Math.round(p));
      var c = document.querySelector('[data-cur]'); if (c) c.textContent = fmtTime(p / 1000);
    }
  }, 500);

  /* ------------------------------------------------------------------ render */
  var root, rq = false, rendering = false, pendingRender = false;
  document.addEventListener('focusout', function (e) { if (pendingRender && e.target && e.target.tagName === 'SELECT') setTimeout(render, 0); });
  document.addEventListener('change', function (e) { if (pendingRender && e.target && e.target.tagName === 'SELECT') setTimeout(render, 0); });
  function scheduleRender() { if (rq) return; rq = true; requestAnimationFrame(function () { rq = false; render(); }); }
  function navLink(hash, name, ic, label) {
    var r = route().name;
    var active = r === name || (name === 'playlists' && r === 'p');
    return h('a', { href: hash, class: active ? 'active' : '', 'aria-current': active ? 'page' : null }, icon(ic), h('span', null, label));
  }
  function render() {
    if (!root) return;
    watchUpdateReconnect();
    if (ui.dragging || nightVolDrag !== null) return;
    var ae = document.activeElement;
    if (ae && ae.tagName === 'SELECT' && root.contains(ae)) { pendingRender = true; return; }
    pendingRender = false;
    var keep = captureFocus(root);
    var r = route();
    var title, body, back = null;
    if (!gotState) {
      body = h('div', { class: 'connect-screen' }, h('div', { class: 'spinner' }),
        h('div', null, online || !everOnline ? t('connecting') : t('offline')),
        !online && retryDelay > 1600 ? h('p', { class: 'small muted' }, t('offline_long')) : null,
        !online && retryDelay > 1600 ? h('button', { class: 'btn', onclick: function () { retryDelay = 1000; connect(); } }, t('retry')) : null);
      title = t('my_jooki');
    } else if (r.name === 'p') {
      var p = pls()[r.arg];
      title = p ? (p.title || '—') : t('playlists');
      back = '#/';
      body = viewPlaylist(r.arg);
    } else if (r.name === 'tokens') { title = t('tokens'); body = viewTokens(); }
    else if (r.name === 'library') { title = t('library'); body = viewLibrary(r.arg); }
    else if (r.name === 'settings') { title = t('settings'); body = viewSettings(); }
    else { title = t('playlists'); body = viewPlaylists(); }
    document.title = gotState ? title + ' — OpenJooki' : 'OpenJooki';
    var conn = h('div', { class: 'conn ' + (online ? 'on' : 'off'), role: 'status', 'aria-live': 'polite' }, h('i'), online ? t('connected') : t('offline'));
    var shell = h('div', { class: 'shell' },
      h('header', { class: 'topbar' },
        back ? h('a', { class: 'icon-btn', href: back, 'aria-label': t('back') }, icon('back')) : h('div', { class: 'brand' }, h('div', { class: 'dot' }, 'J')),
        h('div', { class: 'titles' },
          h('a', { class: 'wordmark', href: '#/', 'aria-label': 'OpenJooki' }, 'Open', h('span', null, 'Jooki')),
          h('h1', null, title)), conn),
      !online && gotState ? h('div', { class: 'banner danger', style: 'margin:12px 16px 0' }, t('offline_long')) : null,
      h('main', { id: 'main' }, body),
      h('nav', { class: 'nav', 'aria-label': 'Navigation' },
        h('a', { class: 'nav-brand', href: '#/', 'aria-hidden': 'true', tabindex: '-1' }, h('span', { class: 'dot' }, 'J'), h('span', null, 'Open', h('b', null, 'Jooki'))),
        navLink('#/', 'playlists', 'list', t('playlists')),
        navLink('#/tokens', 'tokens', 'token', t('tokens')),
        navLink('#/library', 'library', 'lib', t('library')),
        navLink('#/settings', 'settings', 'gear', t('settings'))),
      gotState ? playerBar() : null);
    rendering = true;
    try {
      root.innerHTML = '';
      root.appendChild(shell);
      restoreFocus(root, keep);
    } finally { rendering = false; }
    if (modal && modal.live && volDrag === null && !seeking) {
      var sig = modal.sig ? modal.sig() : '';
      if (sig !== modal.lastSig) { modal.lastSig = sig; renderModal(); }
    }
  }

  /* ------------------------------------------------------------------ boot */
  function boot() {
    document.documentElement.lang = lang;
    root = document.getElementById('app');
    toastBox = h('div', { class: 'toasts', 'aria-live': 'polite' });
    modalRoot = h('div');
    document.body.appendChild(toastBox);
    document.body.appendChild(modalRoot);
    if (navigator.serviceWorker && navigator.serviceWorker.getRegistrations) {
      navigator.serviceWorker.getRegistrations().then(function (rs) { rs.forEach(function (r) { r.unregister(); }); }).catch(function () {});
    }
    render();
    loadAuth(connect);
  }
  window.OJ = { state: S, send: send, version: VERSION };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot); else boot();
})();
