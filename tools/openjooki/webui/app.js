/* OpenJooki web UI — local management page for a Jooki v2.
   Talks to the Jooki only (MQTT over WebSocket on port 8000 + HTTP /upload).
   No tracker, no cloud, no external resource. */
(function () {
  'use strict';

  var CFG = window.OJ_CONFIG || {};
  var VERSION = '2.2.3';

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
      photo_btn: 'Ma photo', photo_remove: 'Retirer l\'image', ed_title: 'La photo du jeton',
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
      air_title: 'Mode avion',
      air_help: 'Coupe le Wi-Fi et le Bluetooth du Jooki pour un temps donné. Les jetons et la musique marchent comme d\'habitude. Pendant ce temps, cette page ne peut plus le joindre.',
      air_for: 'Pendant combien de temps ?', air_h: function (n) { return n + ' h'; },
      air_morning: function (h) { return 'Jusqu\'au matin (' + h + ')'; }, air_boot: 'Jusqu\'à ce qu\'on l\'éteigne et le rallume',
      air_btn: 'Couper le Wi-Fi et le Bluetooth', air_q: 'Passer le Jooki en mode avion ?',
      air_text: function (w) { return 'Le Wi-Fi et le Bluetooth se rallumeront ' + w + '. Et dans tous les cas, éteindre puis rallumer le Jooki remet le Wi-Fi. En attendant, cette page ne peut plus joindre le Jooki ; les jetons et la musique continuent.'; },
      air_at: function (h) { return 'à ' + h; }, air_next_start: 'au prochain allumage',
      air_sent: 'Le Jooki passe en mode avion…',
      air_offline: function (w) { return 'Le Jooki est en mode avion : le Wi-Fi reviendra ' + w + '. Les jetons et la musique marchent. Pour le retrouver plus tôt, éteins le Jooki puis rallume-le.'; },
      air_back: 'Le Jooki est de retour sur le Wi-Fi.',
      bt_title: 'Enceinte ou casque Bluetooth',
      bt_help: 'Allumez l\'enceinte ou le casque et mettez-le en mode appairage (en général : garder le bouton Bluetooth appuyé jusqu\'à ce que le voyant clignote vite). Puis cherchez.',
      bt_search: 'Chercher', bt_searching: 'Recherche… (15 secondes)', bt_connect: 'Connecter', bt_connecting: 'Connexion…',
      bt_none: 'Rien trouvé. Vérifiez que l\'enceinte clignote en mode appairage, puis cherchez encore.',
      bt_failed: 'La connexion n\'a pas marché. Remettez l\'enceinte en mode appairage et réessayez.',
      bt_on: function (n) { return 'Le son sort de : ' + n; },
      bt_on_help: 'Si l\'enceinte s\'éteint, le son revient sur le Jooki. Quand vous la rallumez, le Jooki s\'y reconnecte tout seul.',
      bt_off_btn: 'Ne plus utiliser cette enceinte', bt_off_q: 'Ne plus utiliser cette enceinte ?',
      bt_off_text: 'Le son reviendra sur le Jooki et il ne s\'y reconnectera plus tout seul.',
      bt_air: 'Le Bluetooth est coupé pendant le mode avion.', bt_unnamed: 'Appareil sans nom',
      bt_known: 'Déjà utilisée : allumez-la simplement, pas besoin du mode appairage',
      nothing_playing: 'Rien en lecture', nothing_hint: 'Pose un jeton ou choisis une playlist',
      sp_save: 'Mettre sur un personnage', sp_save_title: 'Mettre cette musique Spotify sur un personnage',
      sp_save_help: 'Pose ensuite le personnage sur le Jooki : il relancera cette playlist Spotify, même sans le téléphone. Le compte Spotify doit rester connecté au Jooki.',
      sp_pick_char: 'Choisis un personnage', sp_saving: 'Spotify enregistre…',
      sp_saved: function (c, n) { return 'C\'est fait : ' + c + ' lance « ' + n + ' »'; },
      sp_timeout: 'Spotify n\'a pas répondu. Relance la musique dans l\'appli Spotify et réessaie.',
      err_sp_not_playing: 'Lance d\'abord la musique sur le Jooki depuis l\'appli Spotify.',
      sp_playlist: 'Playlist Spotify', sp_playlist_help: 'Cette playlist se joue depuis Spotify : on ne peut pas y ajouter de fichiers. Pour changer la musique, fais-la jouer dans Spotify et remets-la sur le personnage.',
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
      wifi_bt: 'Déménagement, nouvelle box, nouveau mot de passe ? Reconnectez-le par Bluetooth depuis un téléphone Android ou un ordinateur : ',
      wifi_bt_name: function (n) { return 'Dans la liste, il s\'appelle ' + n + '.'; },
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
      ssh_key_l: 'Clé publique SSH', ssh_key_help: 'Colle ta clé publique (une ligne qui commence par ssh-ed25519 ou ssh-rsa). Le Jooki la garde, même après une mise à jour.',
      ssh_key_add: 'Ajouter la clé', ssh_key_clear: 'Oublier les clés', ssh_key_added: 'Clé ajoutée',
      ssh_keys_n: function (n) { return n ? (n + (n > 1 ? ' clés enregistrées' : ' clé enregistrée')) : 'Aucune clé enregistrée'; },
      err_ssh_key: 'Ce n\'est pas une clé publique SSH (une ligne ssh-ed25519… ou ssh-rsa…).', err_ssh_closed: 'Ouvre d\'abord l\'accès de maintenance.',
      mqtt_label: 'Domotique (MQTT sur le réseau)', mqtt_help: 'Pour Home Assistant. Désactivée par défaut.',
      mqtt_host_l: 'Hôte', mqtt_port_l: 'Port', mqtt_user_l: 'Utilisateur', mqtt_pass_l: 'Mot de passe',
      parent_label: 'Code parent', parent_help: 'Un code à 4 chiffres empêche enfants et invités de changer les réglages (supprimer une playlist, le Wi-Fi, lancer une mise à jour).',
      parent_set: 'Définir un code', parent_change: 'Changer le code', parent_off: 'Désactiver',
      parent_prompt: 'Entre le code parent', parent_new: 'Code à 4 chiffres', parent_cur: 'Code actuel', parent_bad: 'Code incorrect',
      parent_reset: 'Code oublié ? Appuie 10 secondes sur ◀ et ▶ ensemble sur le Jooki.',
      flat_tok: 'Jeton plat', thanks_tok: 'Jeton Merci',
      own_hint: 'Ce jeton est un personnage à lui tout seul : donne-lui un nom, une image et sa playlist.',
      flat_shared_hint: 'Les jetons plats qui n\'ont pas encore leur propre playlist lancent celle-ci.',
      lib_pick: 'Choisir une image', lib_search_ph: 'Chercher : chat, fusée, dodo…', lib_loading: 'Chargement des images…',
      lib_fail: 'Les images n\'ont pas pu être chargées. Réessaie.', lib_none: function (q) { return 'Aucune image pour « ' + q + ' ».'; },
      lib_n: function (n) { return n + (n > 1 ? ' images' : ' image'); }, lib_set: function (n) { return 'Image choisie : ' + n; },
      s_listen: 'Écoute', s_kids: 'Mode enfant', s_bt: 'Enceinte ou casque', s_none: 'Aucun', s_night_trip: 'Coucher et voyage',
      s_general: 'Général', s_parents: 'Parents', s_advanced: 'Avancé', s_on: 'Activé', s_off: 'Désactivé',
      s_uptodate: 'À jour', s_avail: function (v) { return v + ' dispo'; }, s_storage_free: 'libres', s_open: 'Ouvert', s_closed: 'Fermé',
      s_home: 'Domotique', s_home_sub: 'Home Assistant', s_maint: 'Accès de maintenance', s_maint_sub: 'SSH, pour les bricoleurs',
      disc_add: 'Ajouter des disques', disc_drop: 'Glisse ici les dossiers de tes disques : chaque dossier devient une playlist',
      disc_hint: function (k) { return 'Les FLAC et WAV sont convertis en MP3 ' + k + ' kbps sur ton ordinateur, avant l\'envoi.'; },
      converting: function (k) { return 'Conversion en MP3 ' + k + ' kbps'; }, queued_conv: function (k) { return 'En attente (sera converti en MP3 ' + k + ' kbps)'; },
      up_conv_fail: 'Ce navigateur n\'a pas pu lire ce fichier (essaie Chrome ou Firefox sur un ordinateur)',
      disc_progress: function (d, n) { return d + ' / ' + n + (n > 1 ? ' pistes' : ' piste'); },
      disc_errors: function (n) { return n + (n > 1 ? ' pistes n\'ont pas pu être envoyées' : ' piste n\'a pas pu être envoyée'); },
      disc_created: function (n) { return 'Playlist créée : ' + n; },
      s_mp3: 'Qualité des MP3', s_mp3_sub: 'Pour les FLAC et WAV envoyés', s_mp3_192: '192 kbps — le plus léger', s_mp3_256: '256 kbps — recommandé', s_mp3_320: '320 kbps — le plus fin',
      s_mp3_foot: 'Les FLAC et WAV envoyés au Jooki sont convertis en MP3 sur ton ordinateur ou ton téléphone : un disque prend trois fois moins de place. 256 kbps suffit largement pour l\'enceinte du Jooki et un casque Bluetooth. Ce choix ne vaut que pour cet appareil.',
      s_theme: 'Apparence', s_theme_auto: 'Automatique', s_theme_light: 'Clair', s_theme_dark: 'Sombre',
      s_theme_foot: 'Automatique : comme le téléphone. Ce choix ne vaut que pour ce téléphone.',
      s_party: 'Sapin de Noël', s_party_sub: 'Toutes les couleurs des lumières, pendant 5 secondes', s_party_done: 'Regarde ton Jooki !',
      s_parent_foot: 'Un code à 4 chiffres empêche les enfants et les invités de changer les réglages.',
      s_wifi_net: 'Réseau', s_wifi_signal: 'Signal', s_wifi_drops: 'Coupures depuis le démarrage', s_wifi_page: 'Adresse de la page',
      s_wifi_change: 'Changer de réseau', s_air_for: 'Pendant combien de temps ?', s_lang_foot: 'La langue de cette page sur ce téléphone.',
      s_connect_info: 'Pour te connecter', s_night_hours: 'Horaires', s_night_during: 'Pendant la nuit', s_update: 'Mise à jour'
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
      photo_btn: 'My photo', photo_remove: 'Remove the picture', ed_title: 'The token\'s photo',
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
      air_title: 'Airplane mode',
      air_help: 'Switches the Jooki\'s Wi-Fi and Bluetooth off for a while. Tokens and music work as usual. Meanwhile this page cannot reach it.',
      air_for: 'For how long?', air_h: function (n) { return n + ' h'; },
      air_morning: function (h) { return 'Until the morning (' + h + ')'; }, air_boot: 'Until it is switched off and on again',
      air_btn: 'Switch Wi-Fi and Bluetooth off', air_q: 'Put the Jooki in airplane mode?',
      air_text: function (w) { return 'Wi-Fi and Bluetooth will come back ' + w + '. And in any case, switching the Jooki off and on again brings the Wi-Fi back. Meanwhile this page cannot reach the Jooki; tokens and music carry on.'; },
      air_at: function (h) { return 'at ' + h; }, air_next_start: 'at the next start',
      air_sent: 'The Jooki is going into airplane mode…',
      air_offline: function (w) { return 'The Jooki is in airplane mode: the Wi-Fi will be back ' + w + '. Tokens and music work. To get it back sooner, switch the Jooki off and on again.'; },
      air_back: 'The Jooki is back on the Wi-Fi.',
      bt_title: 'Bluetooth speaker or headphones',
      bt_help: 'Switch the speaker or headphones on and put them in pairing mode (usually: hold the Bluetooth button until the light blinks fast). Then search.',
      bt_search: 'Search', bt_searching: 'Searching… (15 seconds)', bt_connect: 'Connect', bt_connecting: 'Connecting…',
      bt_none: 'Nothing found. Check that the speaker blinks in pairing mode, then search again.',
      bt_failed: 'The connection did not work. Put the speaker in pairing mode again and retry.',
      bt_on: function (n) { return 'Sound plays on: ' + n; },
      bt_on_help: 'If the speaker switches off, the sound comes back to the Jooki. When you switch it on again, the Jooki reconnects by itself.',
      bt_off_btn: 'Stop using this speaker', bt_off_q: 'Stop using this speaker?',
      bt_off_text: 'The sound will come back to the Jooki and it will no longer reconnect to it by itself.',
      bt_air: 'Bluetooth is off during airplane mode.', bt_unnamed: 'Unnamed device',
      bt_known: 'Used before: just switch it on, no pairing mode needed',
      nothing_playing: 'Nothing playing', nothing_hint: 'Put a token or pick a playlist',
      sp_save: 'Put on a character', sp_save_title: 'Put this Spotify music on a character',
      sp_save_help: 'Then put the character on the Jooki: it plays this Spotify playlist again, even without the phone. The Spotify account must stay connected to the Jooki.',
      sp_pick_char: 'Pick a character', sp_saving: 'Spotify is saving…',
      sp_saved: function (c, n) { return 'Done: ' + c + ' plays “' + n + '”'; },
      sp_timeout: 'Spotify did not answer. Play the music again in the Spotify app and try again.',
      err_sp_not_playing: 'First play the music on the Jooki from the Spotify app.',
      sp_playlist: 'Spotify playlist', sp_playlist_help: 'This playlist plays from Spotify: files cannot be added to it. To change the music, play it in Spotify and put it on the character again.',
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
      wifi_bt: 'Moved house, new box, new password? Reconnect it over Bluetooth from an Android phone or a computer: ',
      wifi_bt_name: function (n) { return 'In the list, it is called ' + n + '.'; },
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
      ssh_key_l: 'SSH public key', ssh_key_help: 'Paste your public key (one line starting with ssh-ed25519 or ssh-rsa). The Jooki keeps it, even after an update.',
      ssh_key_add: 'Add the key', ssh_key_clear: 'Forget the keys', ssh_key_added: 'Key added',
      ssh_keys_n: function (n) { return n ? (n + (n > 1 ? ' keys saved' : ' key saved')) : 'No key saved'; },
      err_ssh_key: 'This is not an SSH public key (one line ssh-ed25519… or ssh-rsa…).', err_ssh_closed: 'Open the maintenance access first.',
      mqtt_label: 'Home automation (MQTT on the network)', mqtt_help: 'For Home Assistant. Off by default.',
      mqtt_host_l: 'Host', mqtt_port_l: 'Port', mqtt_user_l: 'User', mqtt_pass_l: 'Password',
      parent_label: 'Parent code', parent_help: 'A 4-digit code stops children and guests from changing settings (deleting a playlist, Wi-Fi, starting an update).',
      parent_set: 'Set a code', parent_change: 'Change the code', parent_off: 'Turn off',
      parent_prompt: 'Enter the parent code', parent_new: '4-digit code', parent_cur: 'Current code', parent_bad: 'Wrong code',
      parent_reset: 'Forgot the code? Hold ◀ and ▶ together for 10 seconds on the Jooki.',
      flat_tok: 'Flat token', thanks_tok: 'Thank-you token',
      own_hint: 'This token is a character of its own: give it a name, a picture and its playlist.',
      flat_shared_hint: 'Flat tokens that have no playlist of their own yet start this one.',
      lib_pick: 'Choose a picture', lib_search_ph: 'Search: cat, rocket, sleep…', lib_loading: 'Loading the pictures…',
      lib_fail: 'The pictures could not be loaded. Try again.', lib_none: function (q) { return 'No picture for “' + q + '”.'; },
      lib_n: function (n) { return n + (n > 1 ? ' pictures' : ' picture'); }, lib_set: function (n) { return 'Picture chosen: ' + n; },
      s_listen: 'Listening', s_kids: 'Kids mode', s_bt: 'Speaker or headphones', s_none: 'None', s_night_trip: 'Bedtime and travel',
      s_general: 'General', s_parents: 'Parents', s_advanced: 'Advanced', s_on: 'On', s_off: 'Off',
      s_uptodate: 'Up to date', s_avail: function (v) { return v + ' available'; }, s_storage_free: 'free', s_open: 'Open', s_closed: 'Closed',
      s_home: 'Home automation', s_home_sub: 'Home Assistant', s_maint: 'Maintenance access', s_maint_sub: 'SSH, for tinkerers',
      disc_add: 'Add albums', disc_drop: 'Drop your album folders here: each folder becomes a playlist',
      disc_hint: function (k) { return 'FLAC and WAV files are turned into MP3 at ' + k + ' kbps on your computer, before they are sent.'; },
      converting: function (k) { return 'Converting to MP3 ' + k + ' kbps'; }, queued_conv: function (k) { return 'Waiting (will be converted to MP3 ' + k + ' kbps)'; },
      up_conv_fail: 'This browser could not read this file (try Chrome or Firefox on a computer)',
      disc_progress: function (d, n) { return d + ' / ' + n + (n > 1 ? ' tracks' : ' track'); },
      disc_errors: function (n) { return n + (n > 1 ? ' tracks could not be sent' : ' track could not be sent'); },
      disc_created: function (n) { return 'Playlist created: ' + n; },
      s_mp3: 'MP3 quality', s_mp3_sub: 'For the FLAC and WAV you send', s_mp3_192: '192 kbps — lightest', s_mp3_256: '256 kbps — recommended', s_mp3_320: '320 kbps — finest',
      s_mp3_foot: 'FLAC and WAV files sent to the Jooki are turned into MP3 on your computer or phone: an album takes three times less space. 256 kbps is plenty for the Jooki\'s speaker and Bluetooth headphones. This choice is for this device only.',
      s_theme: 'Appearance', s_theme_auto: 'Automatic', s_theme_light: 'Light', s_theme_dark: 'Dark',
      s_theme_foot: 'Automatic: like the phone. This choice is for this phone only.',
      s_party: 'Christmas tree', s_party_sub: 'All the colours of the lights, for 5 seconds', s_party_done: 'Look at your Jooki!',
      s_parent_foot: 'A 4-digit code stops children and guests from changing the settings.',
      s_wifi_net: 'Network', s_wifi_signal: 'Signal', s_wifi_drops: 'Drops since start', s_wifi_page: 'Page address',
      s_wifi_change: 'Change network', s_air_for: 'For how long?', s_lang_foot: 'The language of this page on this phone.',
      s_connect_info: 'To connect', s_night_hours: 'Hours', s_night_during: 'During the night', s_update: 'Update'
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
      photo_btn: 'Mijn foto', photo_remove: 'Plaatje weghalen', ed_title: 'De foto van het figuurtje',
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
      air_title: 'Vliegtuigmodus',
      air_help: 'Zet de wifi en bluetooth van de Jooki een tijdje uit. Figuurtjes en muziek werken gewoon. Ondertussen kan deze pagina hem niet bereiken.',
      air_for: 'Hoe lang?', air_h: function (n) { return n + ' u'; },
      air_morning: function (h) { return 'Tot de ochtend (' + h + ')'; }, air_boot: 'Tot hij uit- en weer aangezet wordt',
      air_btn: 'Wifi en bluetooth uitzetten', air_q: 'De Jooki in vliegtuigmodus zetten?',
      air_text: function (w) { return 'Wifi en bluetooth komen terug ' + w + '. En hoe dan ook: de Jooki uit- en weer aanzetten brengt de wifi terug. Ondertussen kan deze pagina de Jooki niet bereiken; figuurtjes en muziek gaan gewoon door.'; },
      air_at: function (h) { return 'om ' + h; }, air_next_start: 'bij de volgende start',
      air_sent: 'De Jooki gaat in vliegtuigmodus…',
      air_offline: function (w) { return 'De Jooki staat in vliegtuigmodus: de wifi komt terug ' + w + '. Figuurtjes en muziek werken. Wil je hem eerder terug, zet de Jooki dan uit en weer aan.'; },
      air_back: 'De Jooki is terug op de wifi.',
      bt_title: 'Bluetooth-speaker of koptelefoon',
      bt_help: 'Zet de speaker of koptelefoon aan en in koppelmodus (meestal: de bluetoothknop ingedrukt houden tot het lampje snel knippert). Zoek dan.',
      bt_search: 'Zoeken', bt_searching: 'Zoeken… (15 seconden)', bt_connect: 'Verbinden', bt_connecting: 'Verbinden…',
      bt_none: 'Niets gevonden. Kijk of de speaker knippert in koppelmodus en zoek opnieuw.',
      bt_failed: 'Verbinden is niet gelukt. Zet de speaker opnieuw in koppelmodus en probeer het nog eens.',
      bt_on: function (n) { return 'Het geluid speelt op: ' + n; },
      bt_on_help: 'Gaat de speaker uit, dan komt het geluid terug op de Jooki. Zet je hem weer aan, dan verbindt de Jooki vanzelf opnieuw.',
      bt_off_btn: 'Deze speaker niet meer gebruiken', bt_off_q: 'Deze speaker niet meer gebruiken?',
      bt_off_text: 'Het geluid komt terug op de Jooki en hij verbindt niet meer vanzelf met deze speaker.',
      bt_air: 'Bluetooth staat uit tijdens de vliegtuigmodus.', bt_unnamed: 'Apparaat zonder naam',
      bt_known: 'Eerder gebruikt: gewoon aanzetten, koppelmodus is niet nodig',
      nothing_playing: 'Er speelt niets', nothing_hint: 'Zet een figuurtje neer of kies een afspeellijst',
      sp_save: 'Op een figuurtje zetten', sp_save_title: 'Deze Spotify-muziek op een figuurtje zetten',
      sp_save_help: 'Zet daarna het figuurtje op de Jooki: het speelt deze Spotify-afspeellijst weer af, ook zonder telefoon. Het Spotify-account moet met de Jooki verbonden blijven.',
      sp_pick_char: 'Kies een figuurtje', sp_saving: 'Spotify slaat op…',
      sp_saved: function (c, n) { return 'Klaar: ' + c + ' speelt „' + n + '”'; },
      sp_timeout: 'Spotify antwoordde niet. Speel de muziek opnieuw af in de Spotify-app en probeer het nog eens.',
      err_sp_not_playing: 'Speel eerst de muziek op de Jooki af vanuit de Spotify-app.',
      sp_playlist: 'Spotify-afspeellijst', sp_playlist_help: 'Deze afspeellijst speelt vanuit Spotify: er kunnen geen bestanden aan worden toegevoegd. Om de muziek te veranderen, speel ze af in Spotify en zet ze opnieuw op het figuurtje.',
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
      wifi_bt: 'Verhuisd, nieuwe router, nieuw wachtwoord? Verbind hem opnieuw via bluetooth vanaf een Android-telefoon of een computer: ',
      wifi_bt_name: function (n) { return 'In de lijst heet hij ' + n + '.'; },
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
      ssh_key_l: 'Openbare SSH-sleutel', ssh_key_help: 'Plak je openbare sleutel (één regel die begint met ssh-ed25519 of ssh-rsa). De Jooki bewaart hem, ook na een update.',
      ssh_key_add: 'Sleutel toevoegen', ssh_key_clear: 'Sleutels vergeten', ssh_key_added: 'Sleutel toegevoegd',
      ssh_keys_n: function (n) { return n ? (n + (n > 1 ? ' sleutels bewaard' : ' sleutel bewaard')) : 'Geen sleutel bewaard'; },
      err_ssh_key: 'Dit is geen openbare SSH-sleutel (één regel ssh-ed25519… of ssh-rsa…).', err_ssh_closed: 'Open eerst de onderhoudstoegang.',
      mqtt_label: 'Domotica (MQTT op het netwerk)', mqtt_help: 'Voor Home Assistant. Standaard uit.',
      mqtt_host_l: 'Host', mqtt_port_l: 'Poort', mqtt_user_l: 'Gebruiker', mqtt_pass_l: 'Wachtwoord',
      parent_label: 'Oudercode', parent_help: 'Een 4-cijferige code voorkomt dat kinderen en gasten instellingen wijzigen (afspeellijst verwijderen, wifi, een update starten).',
      parent_set: 'Code instellen', parent_change: 'Code wijzigen', parent_off: 'Uitschakelen',
      parent_prompt: 'Voer de oudercode in', parent_new: '4-cijferige code', parent_cur: 'Huidige code', parent_bad: 'Onjuiste code',
      parent_reset: 'Code vergeten? Houd ◀ en ▶ 10 seconden samen ingedrukt op de Jooki.',
      flat_tok: 'Plat figuurtje', thanks_tok: 'Bedankt-figuurtje',
      own_hint: 'Dit figuurtje is een personage op zich: geef het een naam, een plaatje en een afspeellijst.',
      flat_shared_hint: 'Platte figuurtjes die nog geen eigen afspeellijst hebben, starten deze.',
      lib_pick: 'Kies een plaatje', lib_search_ph: 'Zoek: kat, raket, slapen…', lib_loading: 'Plaatjes laden…',
      lib_fail: 'De plaatjes konden niet geladen worden. Probeer opnieuw.', lib_none: function (q) { return 'Geen plaatje voor “' + q + '”.'; },
      lib_n: function (n) { return n + (n > 1 ? ' plaatjes' : ' plaatje'); }, lib_set: function (n) { return 'Plaatje gekozen: ' + n; },
      s_listen: 'Luisteren', s_kids: 'Kindermodus', s_bt: 'Speaker of koptelefoon', s_none: 'Geen', s_night_trip: 'Bedtijd en reizen',
      s_general: 'Algemeen', s_parents: 'Ouders', s_advanced: 'Geavanceerd', s_on: 'Aan', s_off: 'Uit',
      s_uptodate: 'Bijgewerkt', s_avail: function (v) { return v + ' beschikbaar'; }, s_storage_free: 'vrij', s_open: 'Open', s_closed: 'Dicht',
      s_home: 'Domotica', s_home_sub: 'Home Assistant', s_maint: 'Onderhoudstoegang', s_maint_sub: 'SSH, voor knutselaars',
      disc_add: 'Albums toevoegen', disc_drop: 'Sleep de mappen van je albums hierheen: elke map wordt een afspeellijst',
      disc_hint: function (k) { return 'FLAC- en WAV-bestanden worden op je computer omgezet naar MP3 ' + k + ' kbps, voordat ze verstuurd worden.'; },
      converting: function (k) { return 'Omzetten naar MP3 ' + k + ' kbps'; }, queued_conv: function (k) { return 'Wachten (wordt omgezet naar MP3 ' + k + ' kbps)'; },
      up_conv_fail: 'Deze browser kon dit bestand niet lezen (probeer Chrome of Firefox op een computer)',
      disc_progress: function (d, n) { return d + ' / ' + n + (n > 1 ? ' nummers' : ' nummer'); },
      disc_errors: function (n) { return n + (n > 1 ? ' nummers konden niet verstuurd worden' : ' nummer kon niet verstuurd worden'); },
      disc_created: function (n) { return 'Afspeellijst gemaakt: ' + n; },
      s_mp3: 'MP3-kwaliteit', s_mp3_sub: 'Voor de FLAC en WAV die je verstuurt', s_mp3_192: '192 kbps — het lichtst', s_mp3_256: '256 kbps — aanbevolen', s_mp3_320: '320 kbps — het fijnst',
      s_mp3_foot: 'FLAC- en WAV-bestanden die naar de Jooki gaan, worden op je computer of telefoon omgezet naar MP3: een album neemt drie keer minder ruimte in. 256 kbps is ruim genoeg voor de luidspreker van de Jooki en een Bluetooth-koptelefoon. Deze keuze geldt alleen voor dit apparaat.',
      s_theme: 'Weergave', s_theme_auto: 'Automatisch', s_theme_light: 'Licht', s_theme_dark: 'Donker',
      s_theme_foot: 'Automatisch: zoals de telefoon. Deze keuze geldt alleen voor deze telefoon.',
      s_party: 'Kerstboom', s_party_sub: 'Alle kleuren van de lampjes, 5 seconden lang', s_party_done: 'Kijk naar je Jooki!',
      s_parent_foot: 'Een code van 4 cijfers voorkomt dat kinderen en gasten instellingen wijzigen.',
      s_wifi_net: 'Netwerk', s_wifi_signal: 'Signaal', s_wifi_drops: 'Onderbrekingen sinds de start', s_wifi_page: 'Adres van de pagina',
      s_wifi_change: 'Ander netwerk', s_air_for: 'Hoe lang?', s_lang_foot: 'De taal van deze pagina op deze telefoon.',
      s_connect_info: 'Om te verbinden', s_night_hours: 'Uren', s_night_during: 'Tijdens de nacht', s_update: 'Update'
    }
  };
  var LANGS = [['en', 'English'], ['fr', 'Français'], ['nl', 'Nederlands']];
  function lsGet(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }
  function lsSet(k, v) { try { localStorage.setItem(k, v); } catch (e) {} }
  // English by default; French or Dutch only when the browser itself is set to that language
  var lang = lsGet('oj.lang') || (navigator.language || 'en').slice(0, 2).toLowerCase();
  if (!T[lang]) lang = 'en';
  // Appearance, kept on this phone: 'auto' follows the phone, 'light' / 'dark' force it (app.css, html[data-theme])
  var THEMES = ['auto', 'light', 'dark'];
  var theme = lsGet('oj.theme');
  if (THEMES.indexOf(theme) < 0) theme = 'auto';
  function applyTheme() { if (theme === 'auto') document.documentElement.removeAttribute('data-theme'); else document.documentElement.setAttribute('data-theme', theme); }
  applyTheme();
  function setTheme(v) { theme = v; lsSet('oj.theme', v); applyTheme(); render(); }
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
  // A token that is a character of its own (docs/23 §4): a foreign NFC tag "tag.<uid>" (amiibo,
  // sticker), a flat token "flat.<uid>" or a Thank-you token "thanks.<uid>" (one code for all of
  // them). Named by its nickname, else its kind + the end of its id; it can carry a picture.
  var OWN = { tag: 'nfc_tag', flat: 'flat_tok', thanks: 'thanks_tok' };
  function ownParts(id) { var m = /^(tag|flat|thanks)\.([0-9A-Fa-f]{14})$/.exec(id || ''); return m ? { kind: m[1], uid: m[2] } : null; }
  function ownUid(id) { var o = ownParts(id); return o ? o.uid : null; }
  function foreignUid(id) { var o = ownParts(id); return o && o.kind === 'tag' ? o.uid : null; }   // the ESP32 never says it was taken off
  function charName(id) {
    var o = ownParts(id);
    // the flat tokens of one batch differ only by the start of their id (04 03AA 6AE74C81, 04 333F 6AE74C81…)
    if (o) { var tk = S.db.tokens[o.uid]; return (tk && tk.name) || (t(OWN[o.kind]) + ' ' + (o.kind === 'tag' ? o.uid.slice(-4) : o.uid.slice(2, 6))); }
    var c = charInfo(id); return c[lang] || c.fr;
  }
  // a token's picture: "lib:<id>" = the page's library (tokimg/), else the photo's own address
  function tokImgSrc(v) {
    v = String(v || '');
    if (/^lib:[a-z0-9_]+$/.test(v)) return '/tokimg/' + v.slice(4) + '.webp';
    return /^\/artwork\/tok_[0-9A-Fa-f]+\.png\?v=\d+$/.test(v) ? v : null;
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
    plane: '<path d="M17.8 19.2 16 11l3.5-3.5C21 6 21.5 4 21 3c-1-.5-3 0-4.5 1.5L13 8 4.8 6.2c-.5-.1-.9.1-1.1.5l-.3.5c-.2.5-.1 1 .3 1.3L9 12l-2 3H4l-1 1 3 2 2 3 1-1v-3l3-2 3.5 5.3c.3.4.8.5 1.3.3l.5-.2c.4-.3.6-.7.5-1.2z"/>',
    note: '<path d="M9 18V5l11-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="17" cy="16" r="3"/>',
    link0: '<path d="M8 12h8"/>',
    moon: '<path d="M20 14.5A8.5 8.5 0 0 1 9.5 4a8.5 8.5 0 1 0 10.5 10.5z"/>',
    contrast: '<circle cx="12" cy="12" r="8.5"/><path d="M12 3.5a8.5 8.5 0 0 1 0 17z" fill="currentColor"/>',
    sort: '<path d="M4 6h9M4 12h7M4 18h5M17 4v16M14 17l3 3 3-3"/>',
    sparkle: '<path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z"/><path d="M19 15.5l.7 1.8 1.8.7-1.8.7-.7 1.8-.7-1.8-1.8-.7 1.8-.7z"/>',
    camera: '<path d="M4 8h3l2-3h6l2 3h3v11H4z"/><circle cx="12" cy="13" r="3.5"/>',
    chev: '<path d="M9 6l6 6-6 6"/>',
    bt: '<path d="M7 7l10 10-5 4V3l5 4L7 17"/>',
    wifi: '<path d="M2.5 9a14 14 0 0 1 19 0M5.5 12.3a9.5 9.5 0 0 1 13 0M8.6 15.5a5 5 0 0 1 6.8 0"/><path d="M12 19h.01" stroke-width="3"/>',
    globe: '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c3 3.3 3 14.7 0 18M12 3c-3 3.3-3 14.7 0 18"/>',
    lock: '<rect x="5" y="10.5" width="14" height="10" rx="2.5"/><path d="M8 10.5V8a4 4 0 0 1 8 0v2.5"/>',
    home: '<path d="M3.5 11L12 4l8.5 7M6 9.5V20h12V9.5"/>',
    wrench: '<path d="M14.5 4a5 5 0 0 0-4.6 6.9L4 16.8V20h3.2l5.9-5.9A5 5 0 0 0 20 9.5l-3 3-3-1-1-3 3-3a5 5 0 0 0-1.5-.5z"/>',
    up: '<path d="M12 19V6M6 11l6-6 6 6"/>',
    bat: '<rect x="2.5" y="7" width="17" height="10" rx="2.5"/><path d="M22 10.5v3"/>',
    disk: '<rect x="4" y="3" width="16" height="18" rx="3"/><circle cx="12" cy="10" r="3"/><path d="M8 17h8"/>',
    tag: '<path d="M3 12V4h8l10 10-8 8z"/><circle cx="7.5" cy="8" r="1"/>'
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
      // back after an airplane mode (not a hiccup right after asking for it)
      if (airplane && Date.now() - airplane.sent > 15000) { setAirplane(null); toast(t('air_back')); }
      client.subscribe('/j/web/output/#');
      send('GET_STATE', {});
      sendTime();
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
  // airplane mode started from the page (docs/24): the Jooki leaves the Wi-Fi on purpose, so this
  // browser remembers until when and says so, instead of "the Jooki is not answering".
  var airplane = null;
  try { airplane = JSON.parse(lsGet('oj.airplane') || 'null'); } catch (e) { airplane = null; }
  function setAirplane(v) { airplane = v; lsSet('oj.airplane', v ? JSON.stringify(v) : ''); }
  function airplaneNow() {
    if (!airplane) return null;
    if (airplane.ends && Date.now() > airplane.ends + 5 * 60000) { setAirplane(null); return null; }   // long over: back to normal
    return airplane;
  }
  function airplaneWhen(a) {
    if (!a.ends) return t('air_next_start');
    var e = new Date(a.ends);
    return t('air_at', hm(e.getHours() * 60 + e.getMinutes()));
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
  // The Jooki has no clock of its own: started without Internet it believes it is 1970, and night
  // mode stays off. This phone's time goes with every connection; the Jooki takes it only while its
  // own clock is unset (no code needed, nothing else changes).
  function sendTime() {
    var utc = Math.floor(Date.now() / 1000);
    if (!client || !online || utc < 1704067200) return;
    client.publish('/j/web/input/OJ_TIME', JSON.stringify({ utc: utc }));
  }
  var waiters = [], autoChecked = false, staleReload = false, onCmdError = null;
  // The Jooki serves index.html without cache headers: a phone may keep the old page after an
  // update (system 2.0.5, page 2.0.4). If the Jooki is newer than this page, load it again once,
  // under a new address so the phone cannot reuse its copy (?v= also stops any loop).
  function reloadIfStale() {
    var v = S.device.openjooki;
    if (staleReload || !v || !newer(v, VERSION) || location.search.indexOf('v=' + v) >= 0) return;
    staleReload = true;
    var busy = upd.state === 'running' || upd.state === 'rebooting';   // just updated: let the "done" toast show first
    setTimeout(function () { location.replace(location.pathname + '?v=' + encodeURIComponent(v) + location.hash); }, busy ? 3000 : 0);
  }
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
      reloadIfStale();
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
      if (onCmdError) { var f = onCmdError; onCmdError = null; f(data); }
    }
  }
  function errorText(msg) {
    msg = String(msg || '');
    if (msg === 'TRASH_READONLY') return t('err_readonly');
    if (msg === 'ERR_INTERNAL') return t('err_internal');
    if (msg === 'empty title') return t('err_empty_title');
    if (msg === 'invalid stream url') return t('err_radio');
    if (msg === 'invalid token type') return t('err_unknown_char');
    if (msg === 'Not playing spotify right now') return t('err_sp_not_playing');
    if (msg === 'SSH_KEY_INVALID') return t('err_ssh_key');
    if (msg === 'SSH_CLOSED') return t('err_ssh_closed');
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
      var sheet = h('div', { class: 'sheet' + (modal.cls ? ' ' + modal.cls : ''), role: 'dialog', 'aria-modal': 'true' }, modal.render());
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

  /* ------------------------------------------------------------------ discs: FLAC / WAV -> MP3, in the browser */
  // A disc in FLAC weighs ~300 MB: a twentieth of the Jooki's card. The page turns lossless files into
  // MP3 here, on the phone or computer (the Jooki has neither the power nor the memory, and writing
  // while it plays makes the sound stutter), keeps the tags and a small cover, then sends the MP3 like
  // any other file. Decoding: the browser's own (FLAC since Chrome 56, Firefox 51, Safari 11),
  // resampled to 44.1 kHz; encoding: lamejs (LGPL-3.0, lame.LICENSE.txt) in mp3-worker.js.
  var LOSSLESS = /\.(flac|wav)$/i;
  var MP3_RATES = [192, 256, 320];
  function mp3Kbps() { var v = Number(lsGet('oj.mp3')); return MP3_RATES.indexOf(v) >= 0 ? v : 256; }
  function canConvert() { return !!(window.Worker && (window.OfflineAudioContext || window.webkitOfflineAudioContext)); }
  function readBytes(blob, from, len) {
    return new Promise(function (ok, ko) {
      var fr = new FileReader();
      fr.onload = function () { ok(new Uint8Array(fr.result)); };
      fr.onerror = function () { ko(fr.error); };
      fr.readAsArrayBuffer(blob.slice(from, from + len));
    });
  }
  function u32le(b, i) { return (b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24)) >>> 0; }
  function u32be(b, i) { return ((b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3]) >>> 0; }
  var utf8 = window.TextDecoder ? new TextDecoder('utf-8') : null;
  function utf8At(b, from, len) { return utf8 ? utf8.decode(b.subarray(from, from + len)) : ''; }
  // A FLAC file's tags (Vorbis comments, upper-case keys) and its first picture (front cover first):
  // only the small metadata blocks at its start are read, never the audio.
  function flacTags(file, withPicture) {
    var tags = {};
    if (!/\.flac$/i.test(file.name)) return Promise.resolve(tags);
    var pos = 4;
    function block() {
      return readBytes(file, pos, 4).then(function (hd) {
        if (hd.length < 4) return tags;
        var last = hd[0] & 128, type = hd[0] & 127, len = (hd[1] << 16) | (hd[2] << 8) | hd[3], start = pos + 4;
        pos = start + len;
        var want = type === 4 || (type === 6 && withPicture && len < 16e6 && !(tags.picture && tags.picture.front));
        return (want ? readBytes(file, start, len).then(function (b) { if (type === 4) vorbisTags(b, tags); else flacPicture(b, tags); }) : Promise.resolve())
          .then(function () { return last || pos >= file.size ? tags : block(); });
      });
    }
    return readBytes(file, 0, 4).then(function (m) { return String.fromCharCode(m[0], m[1], m[2], m[3]) === 'fLaC' ? block() : tags; })
      .catch(function () { return tags; });
  }
  function vorbisTags(b, tags) {
    var i = 4 + u32le(b, 0), n = u32le(b, i);
    i += 4;
    for (var k = 0; k < n && i + 4 <= b.length; k++) {
      var len = u32le(b, i), kv = utf8At(b, i + 4, len), eq = kv.indexOf('=');
      i += 4 + len;
      if (eq > 0 && !tags[kv.slice(0, eq).toUpperCase()]) tags[kv.slice(0, eq).toUpperCase()] = kv.slice(eq + 1);
    }
  }
  function flacPicture(b, tags) {
    var kind = u32be(b, 0), ml = u32be(b, 4), mime = utf8At(b, 8, ml), i = 8 + ml;
    i += 4 + u32be(b, i) + 16;   // description, then width, height, depth, colours
    var len = u32be(b, i);
    tags.picture = { mime: mime || 'image/jpeg', data: b.slice(i + 4, i + 4 + len), front: kind === 3 };
  }
  // the cover, at most 300 px (a big cover inside the file slows the Jooki down), as JPEG bytes
  function smallCover(blob) {
    if (!blob || !window.createImageBitmap) return Promise.resolve(null);
    return createImageBitmap(blob).then(function (img) {
      var s = Math.min(1, 300 / Math.max(img.width, img.height)), c = document.createElement('canvas');
      c.width = Math.max(1, Math.round(img.width * s)); c.height = Math.max(1, Math.round(img.height * s));
      c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
      return new Promise(function (ok) { c.toBlob(ok, 'image/jpeg', 0.85); });
    }).then(function (jpg) { return jpg ? readBytes(jpg, 0, jpg.size) : null; }).catch(function () { return null; });
  }
  // An ID3v2.3 tag (UTF-16 text frames, an APIC front cover): what the Jooki reads from an MP3.
  function id3(tags, cover) {
    var frames = [];
    function text(id, v) {
      if (!v) return;
      v = String(v);
      var b = new Uint8Array(5 + v.length * 2);
      b[0] = 1; b[1] = 255; b[2] = 254;
      for (var i = 0; i < v.length; i++) { b[3 + 2 * i] = v.charCodeAt(i) & 255; b[4 + 2 * i] = v.charCodeAt(i) >> 8; }
      frames.push([id, b]);
    }
    var track = tags.TRACKNUMBER, total = tags.TRACKTOTAL || tags.TOTALTRACKS;
    text('TIT2', tags.TITLE); text('TPE1', tags.ARTIST); text('TALB', tags.ALBUM);
    text('TPE2', tags.ALBUMARTIST || tags['ALBUM ARTIST']); text('TCON', tags.GENRE);
    text('TRCK', track && total && String(track).indexOf('/') < 0 ? track + '/' + total : track);
    text('TPOS', tags.DISCNUMBER); text('TYER', (String(tags.DATE || '').match(/\d{4}/) || [])[0]);
    if (cover) {
      var head = [0].concat('image/jpeg'.split('').map(function (c) { return c.charCodeAt(0); }), [0, 3, 0]);
      var pic = new Uint8Array(head.length + cover.length);
      pic.set(head, 0); pic.set(cover, head.length);
      frames.push(['APIC', pic]);
    }
    var size = frames.reduce(function (s, f) { return s + 10 + f[1].length; }, 0), out = new Uint8Array(10 + size), at = 10;
    out.set([73, 68, 51, 3, 0, 0, (size >> 21) & 127, (size >> 14) & 127, (size >> 7) & 127, size & 127], 0);
    frames.forEach(function (f) {
      var n = f[1].length;
      out.set([f[0].charCodeAt(0), f[0].charCodeAt(1), f[0].charCodeAt(2), f[0].charCodeAt(3), (n >>> 24) & 255, (n >> 16) & 255, (n >> 8) & 255, n & 255, 0, 0], at);
      out.set(f[1], at + 10); at += 10 + n;
    });
    return out;
  }
  function decodeAudio(file) {
    return readBytes(file, 0, file.size).then(function (bytes) {
      var Ctx = window.OfflineAudioContext || window.webkitOfflineAudioContext, ctx = new Ctx(2, 1, 44100);
      return new Promise(function (ok, ko) { var p = ctx.decodeAudioData(bytes.buffer, ok, ko); if (p && p.then) p.then(ok, ko); });
    });
  }
  function encodeMp3(audio, kbps, onProgress) {
    return new Promise(function (ok, ko) {
      var w = new Worker('mp3-worker.js?v=' + VERSION);
      var ch = [audio.getChannelData(0)];
      if (audio.numberOfChannels > 1) ch.push(audio.getChannelData(1));
      ch = ch.map(function (c) { return new Float32Array(c); });   // copies the worker may take
      w.onmessage = function (e) {
        var d = e.data;
        if (d.progress !== undefined) { onProgress(d.progress); return; }
        w.terminate();
        if (d.mp3) ok(d.mp3); else ko(new Error(d.error || 'mp3'));
      };
      w.onerror = function (e) { w.terminate(); ko(new Error(e.message || 'mp3 worker')); };
      w.postMessage({ channels: ch, rate: audio.sampleRate, kbps: kbps }, ch.map(function (c) { return c.buffer; }));
    });
  }
  // file (FLAC / WAV) -> an MP3 File with its tags and cover; `cover` = the folder's picture, if any
  function toMp3(file, cover, onProgress) {
    var kbps = mp3Kbps();
    return Promise.all([flacTags(file, true), decodeAudio(file)]).then(function (r) {
      var tags = r[0], pic = tags.picture ? new Blob([tags.picture.data], { type: tags.picture.mime }) : cover;
      return Promise.all([encodeMp3(r[1], kbps, onProgress), smallCover(pic)]).then(function (x) {
        return new File([id3(tags, x[1]), x[0]], file.name.replace(LOSSLESS, '') + '.mp3', { type: 'audio/mpeg' });
      });
    });
  }
  // One file at a time, at most two ahead of the upload (each decoded disc track is ~100 MB of memory).
  var convBusy = false;
  function convPump() {
    if (convBusy) return;
    if (uploads.filter(function (x) { return x.conv && x.converted && x.status === 'queued'; }).length >= 2) return;
    var u = uploads.filter(function (x) { return x.conv && !x.converted && x.status === 'queued'; })[0];
    if (!u) return;
    convBusy = true; u.status = 'converting'; u.progress = 0; render();
    toMp3(u.file, u.cover, function (p) { u.progress = p; updateUploadRow(u); }).then(function (mp3) {
      u.file = mp3; u.name = mp3.name; u.size = mp3.size; u.converted = true; u.status = 'queued'; u.progress = 0; u.cover = null;
    }, function () {
      u.status = 'error'; u.error = t('up_conv_fail'); u.file = null; u.cover = null;
    }).then(function () { convBusy = false; render(); pump(); convPump(); });
  }

  // Folders: a dropped folder (or one chosen with "Add albums") is a disc. Its files come back as
  // groups, one per folder; files dropped loose make one group of their own (dir = null).
  function groupsFromList(files) {
    var groups = {}, order = [];
    Array.prototype.forEach.call(files, function (f) {
      var p = f.webkitRelativePath || '', dir = p.indexOf('/') > 0 ? p.slice(0, p.lastIndexOf('/')) : null;
      if (!groups.hasOwnProperty(dir)) { groups[dir] = []; order.push(dir); }
      groups[dir].push(f);
    });
    return order.map(function (d) { return { dir: d, files: groups[d] }; });
  }
  function groupsFromDrop(dt) {
    var entries = Array.prototype.map.call(dt.items || [], function (it) { return it.webkitGetAsEntry ? it.webkitGetAsEntry() : null; }).filter(Boolean);
    if (!entries.some(function (e) { return e.isDirectory; })) return Promise.resolve(groupsFromList(dt.files));
    var out = [], loose = [];
    function fileOf(e) { return new Promise(function (ok) { e.file(ok, function () { ok(null); }); }); }
    function children(dir) {
      var reader = dir.createReader(), all = [];
      return new Promise(function (ok) {
        (function more() { reader.readEntries(function (b) { if (!b.length) ok(all); else { all = all.concat(b); more(); } }, function () { ok(all); }); })();
      });
    }
    function walk(dir) {   // a folder: its own files are one group, its sub-folders (CD1, CD2…) are walked too
      return children(dir).then(function (list) {
        return Promise.all(list.filter(function (e) { return e.isFile; }).map(fileOf)).then(function (files) {
          files = files.filter(Boolean);
          if (files.length) out.push({ dir: dir.fullPath.replace(/^\//, ''), files: files });
          return list.filter(function (e) { return e.isDirectory; }).reduce(function (c, d) { return c.then(function () { return walk(d); }); }, Promise.resolve());
        });
      });
    }
    return entries.reduce(function (c, e) {
      return c.then(function () { return e.isDirectory ? walk(e) : fileOf(e).then(function (f) { if (f) loose.push(f); }); });
    }, Promise.resolve()).then(function () {
      out.sort(function (a, b) { return natural(a.dir, b.dir); });
      if (loose.length) out.push({ dir: null, files: loose });
      return out;
    });
  }
  var COVER_NAME = /^(cover|folder|front|album|pochette)[^/]*\.(jpe?g|png)$/i;
  function natural(a, b) { return collator().compare(a, b); }
  // one group -> { title, files (disc then track order), cover }; null when it holds no audio
  function discOf(group) {
    var audio = group.files.filter(function (f) { return AUDIO_EXT.test(f.name) && f.size > 5000; });
    if (!audio.length) return Promise.resolve(null);
    var cover = group.files.filter(function (f) { return COVER_NAME.test(f.name); })[0] || null;
    return Promise.all(audio.map(function (f) { return flacTags(f, false); })).then(function (tags) {
      var rows = audio.map(function (f, i) { return { f: f, d: parseInt(tags[i].DISCNUMBER, 10) || 0, n: parseInt(tags[i].TRACKNUMBER, 10) || 0, tags: tags[i] }; });
      rows.sort(function (a, b) { return a.d - b.d || a.n - b.n || natural(a.f.name, b.f.name); });
      var parts = (group.dir || '').split('/'), folder = parts[parts.length - 1] || '';
      var album = (rows.filter(function (r) { return r.tags.ALBUM; })[0] || { tags: {} }).tags.ALBUM;
      if (!album && /^(cd|disc|disk|disque|disco)\s*\d+$/i.test(folder) && parts.length > 1) album = parts[parts.length - 2] + ' – ' + folder;
      return { title: (album || folder || t('new_playlist')).slice(0, 100), files: rows.map(function (r) { return r.f; }), cover: cover };
    });
  }
  function createPlaylist(title) {
    return new Promise(function (ok, ko) {
      var before = Object.keys(pls()), over = false;
      var timer = setTimeout(function () { over = true; ko(new Error('timeout')); }, 20000);
      waiters.push(function (partial) {
        if (over) return true;
        if (!partial.db) return false;
        var fresh = Object.keys(pls()).filter(function (k) { return before.indexOf(k) < 0 && k !== 'TRASH'; })[0];
        if (!fresh) return false;
        clearTimeout(timer); ok(fresh); return true;
      });
      send('PLAYLIST_NEW', { title: title, audiobook: false });
    });
  }
  // Discs dropped on the playlists page: each folder becomes a playlist named after its album, its
  // tracks in disc order. Dropped in a playlist: everything goes into that playlist, folder by folder.
  function addDiscs(groups, playlistId) {
    return groups.reduce(function (chain, g) {
      return chain.then(function () { return discOf(g); }).then(function (d) {
        if (!d) return null;
        if (playlistId || !g.dir) { enqueue(d.files, playlistId || null, { cover: d.cover }); return null; }
        return createPlaylist(d.title).then(function (id) {
          enqueue(d.files, id, { cover: d.cover, disc: { id: ++discSeq, title: d.title } });
          toast(t('disc_created', d.title));
        }, function () { toast(t('up_fail') + ' : ' + d.title, 'error'); });
      });
    }, Promise.resolve());
  }

  /* ------------------------------------------------------------------ uploads */
  var uploads = [], upBusy = false, upSeq = 0;
  var AUDIO_EXT = /\.(mp3|m4a|mp4|aac|ogg|oga|flac|wav|wma|m4b)$/i;
  function enqueue(files, playlistId, opts) {
    opts = opts || {};
    var free = S.device.diskUsage && Number(S.device.diskUsage.available) ? Number(S.device.diskUsage.available) * 1024 : null;
    var reserved = 0, conv = canConvert();
    Array.prototype.forEach.call(files, function (f) {
      var u = { key: ++upSeq, file: f, name: f.name, size: f.size, playlistId: playlistId || null, status: 'queued', progress: 0, error: null,
                conv: conv && LOSSLESS.test(f.name), cover: opts.cover || null, disc: opts.disc || null };
      // the space an MP3 will take: FLAC is ~700 kbit/s or more, WAV 1411
      var need = u.conv ? f.size * mp3Kbps() / (/\.wav$/i.test(f.name) ? 1411 : 700) : f.size;
      if (f.size <= 5000) { u.status = 'error'; u.error = t('up_too_small'); }
      else if (!AUDIO_EXT.test(f.name) && !(f.type && f.type.indexOf('audio/') === 0)) { u.status = 'error'; u.error = t('up_type'); }
      else if (free !== null && reserved + need + 10e6 > free) { u.status = 'error'; u.error = t('up_no_space'); }
      else reserved += need;
      uploads.push(u);
    });
    render();
    convPump();
    pump();
  }
  // A weak Wi-Fi drops connections: a failed or stalled transfer is retried on its own
  // (after the Jooki is back), and a lost answer is checked again after reconnecting.
  var UP_TRIES = 4, UP_STALL_MS = 30000, UP_DELAYS = [3000, 8000, 20000];
  function pump() {
    if (upBusy) return;
    var now = Date.now();
    // in order: a file still to be converted holds back the ones after it (they keep the disc's order)
    var u = uploads.filter(function (x) { return x.status === 'queued' || x.status === 'converting'; })[0];
    if (u && (u.status === 'converting' || (u.conv && !u.converted) || u.retryAt > now)) u = null;
    if (!u) {
      var next = uploads.filter(function (x) { return x.status === 'queued' && x.retryAt; }).map(function (x) { return x.retryAt; })[0];
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
    setTimeout(function () { pump(); convPump(); }, 50);
  }
  function uploadsActive() { return uploads.some(function (u) { return u.status === 'queued' || u.status === 'converting' || u.status === 'uploading' || u.status === 'processing'; }); }
  window.addEventListener('beforeunload', function (e) { if (uploadsActive()) { e.preventDefault(); e.returnValue = t('uploads_running'); return e.returnValue; } });
  function updateUploadRow(u) {
    var el = document.querySelector('[data-up="' + u.key + '"] .bar > i');
    if (el) el.style.width = Math.round(u.progress * 100) + '%';
    var st = document.querySelector('[data-up="' + u.key + '"] .st');
    if (st) st.textContent = upLabel(u) + ' ' + Math.round(u.progress * 100) + ' %';
    if (u.disc) updateDiscRow(u.disc);
  }
  function upLabel(u) { return u.status === 'converting' ? t('converting', mp3Kbps()) : t('uploading'); }
  function uploadsBlock(playlistId) {
    var list = uploads.filter(function (u) { return u.playlistId === (playlistId || null); });
    if (!list.length) return null;
    var anyDone = list.some(function (u) { return u.status === 'done' || u.status === 'error'; });
    return h('div', { class: 'card uploads' },
      list.map(function (u) {
        var st = u.status === 'queued' ? (u.note || (u.conv && !u.converted ? t('queued_conv', mp3Kbps()) : t('queued')))
          : u.status === 'uploading' || u.status === 'converting' ? upLabel(u) + ' ' + Math.round(u.progress * 100) + ' %'
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
    // folders too: their files go into this playlist, folder after folder, in disc order
    z.addEventListener('drop', function (e) { e.preventDefault(); z.classList.remove('over'); if (e.dataTransfer && e.dataTransfer.files.length) groupsFromDrop(e.dataTransfer).then(function (g) { addDiscs(g, playlistId); }); });
    return z;
  }
  var canHover = window.matchMedia && window.matchMedia('(hover: hover) and (pointer: fine)').matches;

  // discs on the playlists page: one line per disc (folder) being sent, with its progress
  var discSeq = 0;
  function discInfo(disc) {
    var list = uploads.filter(function (u) { return u.disc === disc; });
    var done = list.filter(function (u) { return u.status === 'done'; }).length, bad = list.filter(function (u) { return u.status === 'error'; });
    var cur = list.filter(function (u) { return u.status === 'uploading' || u.status === 'processing' || u.status === 'converting'; })[0];
    var st = cur ? cur.name + ' · ' + (cur.status === 'processing' ? t('processing') : upLabel(cur) + ' ' + Math.round(cur.progress * 100) + ' %')
      : done + bad.length < list.length ? t('queued') : bad.length ? t('disc_errors', bad.length) : t('done');
    return { n: list.length, done: done, bad: bad, st: st, frac: (done + bad.length + (cur ? cur.progress : 0)) / Math.max(1, list.length),
             over: done + bad.length === list.length };
  }
  function updateDiscRow(disc) {
    var el = document.querySelector('[data-disc="' + disc.id + '"]');
    if (!el) return;
    var i = discInfo(disc);
    el.querySelector('.bar > i').style.width = Math.round(i.frac * 100) + '%';
    el.querySelector('.st').textContent = i.st;
  }
  function discsBlock() {
    var discs = [];
    uploads.forEach(function (u) { if (u.disc && discs.indexOf(u.disc) < 0) discs.push(u.disc); });
    if (!discs.length) return null;
    var running = discs.some(function (d) { return !discInfo(d).over; });
    return h('div', { class: 'card uploads', 'data-k': 'discs' }, discs.map(function (d) {
      var i = discInfo(d);
      return h('div', { class: 'up' + (i.over ? (i.bad.length ? ' error' : ' done') : ''), 'data-disc': d.id },
        h('div', { class: 'row' }, h('div', { class: 'grow ellipsis' }, '💿 ' + d.title), h('span', { class: 'small muted' }, t('disc_progress', i.done, i.n))),
        h('div', { class: 'bar' }, h('i', { style: 'width:' + Math.round(i.frac * 100) + '%' })),
        h('div', { class: 'st small' }, i.st),
        i.bad.map(function (u) { return h('div', { class: 'small accent-text ellipsis' }, u.name + ' : ' + u.error); }));
    }), running ? null : h('div', { class: 'up' }, h('button', { class: 'btn ghost block', 'data-k': 'discclear', onclick: function () {
      uploads = uploads.filter(function (u) { return !u.disc; }); render();
    } }, t('clear_done'))));
  }
  // "Add albums": a folder picker, on computers (phones cannot pick a folder)
  function discButton() {
    if (!canHover || !('webkitdirectory' in document.createElement('input'))) return null;
    var inp = h('input', { type: 'file', webkitdirectory: true, multiple: true, class: 'sr', 'aria-hidden': 'true', tabindex: '-1', 'data-k': 'discinput',
      onchange: function () { var f = inp.files; if (f && f.length) addDiscs(groupsFromList(f), null); inp.value = ''; } });
    return h('label', { class: 'btn', tabindex: '0', role: 'button', 'data-k': 'discadd',
      onkeydown: function (e) { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); inp.click(); } } }, icon('upload'), t('disc_add'), inp);
  }
  function discDrop() {
    if (!canHover) return null;
    var z = h('div', { class: 'drop', 'data-k': 'discdrop' }, t('disc_drop'), h('div', { class: 'small' }, t('disc_hint', mp3Kbps())));
    z.addEventListener('dragover', function (e) { e.preventDefault(); z.classList.add('over'); });
    z.addEventListener('dragleave', function () { z.classList.remove('over'); });
    z.addEventListener('drop', function (e) { e.preventDefault(); z.classList.remove('over'); if (e.dataTransfer && e.dataTransfer.files.length) groupsFromDrop(e.dataTransfer).then(function (g) { addDiscs(g, null); }); });
    return z;
  }

  /* ------------------------------------------------------------------ token visuals */
  function tokVisual(starId, cls, live) {
    var c = charInfo(starId);
    var el = h('div', { class: 'tok ' + (cls || '') + (live ? ' live' : ''), title: charName(starId) });
    if (!starId) { el.className += ' none'; el.appendChild(icon('token')); return el; }
    var own = ownParts(starId), ftk = own && S.db.tokens[own.uid], src = ftk && tokImgSrc(ftk.image);
    if (src) {   // its picture: from the library, or a photo (a 128 px PNG on the Jooki, see tokenImageEditor)
      var pic = h('img', { src: src, alt: '' });
      pic.onerror = function () { pic.replaceWith(h('span', { class: 'letter' }, (charName(starId) || '?').charAt(0))); };
      el.appendChild(pic); return el;
    }
    if (own && own.kind !== 'tag') c = charInfo(own.kind === 'flat' ? 'Jooki.Flat' : 'Jooki.ThankYou');   // no picture yet: the round token
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
        h('div', { class: 'meta' }, p.spotify ? t('sp_playlist') : t('n_tracks', n) + (total ? ' · ' + fmtTotal(total) : '') + (p.audiobook ? ' · ' + t('audiobook') : '')),
        n || p.spotify ? h('button', { class: 'icon-btn accent play', 'aria-label': t('play') + ' ' + (p.title || ''), onclick: function (e) {
          e.stopPropagation(); send('PLAYLIST_PLAY', { playlistId: p.id }); } }, icon('play')) : null);
      return card;
    });
    cards.push(h('button', { class: 'card pl newpl', onclick: newPlaylistModal, 'data-k': 'newpl' }, icon('plus'), t('new_playlist')));
    var addDisc = discButton();
    return [
      updateAvailable() && upd.state === 'checked' ? h('div', { class: 'banner row', 'data-k': 'updbanner' }, h('span', { class: 'grow' }, t('upd_banner', upd.latest)),
        h('a', { href: '#/settings/update' }, t('upd_see'))) : null,
      un ? h('div', { class: 'banner row' }, h('span', { class: 'grow' }, t('unused_banner', un)),
        h('a', { href: '#/library/unused' }, t('see'))) : null,
      list.length ? null : h('div', { class: 'empty' }, h('div', { class: 'big' }, '🎵'), t('no_playlists')),
      h('div', { class: 'plgrid' }, cards),
      discsBlock(),
      addDisc ? h('div', { class: 'actions', style: 'margin-top:14px' }, addDisc) : null,
      discDrop()
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

  // the grid of characters to pick from (the ones seen on this Jooki first); `none` adds "no token"
  function charGrid(chosen, selfId, pick, none) {
    var seen = {};
    Object.keys(S.db.tokens).forEach(function (k) { var s = S.db.tokens[k] && S.db.tokens[k].starId; if (isUserChar(s)) seen[s] = true; });
    function opt(id) {
      var other = id ? playlistOfChar(id) : null;
      if (other && other.id === selfId) other = null;
      return h('button', { class: 'charopt' + (chosen === id ? ' sel' : ''), 'data-char': id || 'none', 'aria-pressed': chosen === id ? 'true' : 'false',
        onclick: function () { pick(id); renderModal(); } },
        tokVisual(id, 'sm'), h('div', null, id ? charName(id) : t('no_token')), other ? h('div', { class: 'taken' }, t('used_by', other.title || '—')) : null);
    }
    var ids = CHARS.map(function (c) { return c[0]; }).filter(function (id) { return id !== 'Jooki.ThankYou'; });
    Object.keys(seen).forEach(function (s) { if (ids.indexOf(s) < 0) ids.push(s); });
    ids.sort(function (a, b) { return (seen[b] ? 1 : 0) - (seen[a] ? 1 : 0) || charInfo(a).order - charInfo(b).order; });
    return h('div', { class: 'chargrid' }, none ? opt(null) : null, ids.map(opt));
  }
  function charPickerModal(p) {
    var chosen = p.star || null;
    openModal({
      render: function () {
        var other = chosen ? playlistOfChar(chosen) : null;
        if (other && other.id === p.id) other = null;
        return [h('h3', null, t('token_for')), h('p', { class: 'small muted' }, t('token_help')),
          charGrid(chosen, p.id, function (id) { chosen = id; }, true),
          other ? h('div', { class: 'banner', style: 'margin-top:12px' }, t('token_moved', other.title || '—')) : null,
          h('div', { class: 'foot' }, h('button', { class: 'btn', onclick: closeModal }, t('cancel')),
            h('button', { class: 'btn primary', 'data-k': 'charsave', onclick: function () {
              if ((chosen || null) !== (p.star || null)) send('PLAYLIST_UPDATE', { playlist: { id: p.id, star: chosen || false } });
              closeModal();
            } }, t('save')))];
      }
    });
  }

  // What Spotify plays on the Jooki, put on a character (1.x "preset", the Muuselabs app had it):
  // the Jooki asks Spotify for a preset of what plays, the core stores it in a new playlist.
  function spotifySaveModal() {
    var np = S.audio.nowPlaying;
    var name = cleanTitle(np.source || np.track || '') || 'Spotify', chosen = null, saving = false;
    function save() {
      var v = name.trim();
      if (!v || !chosen || saving) return;
      saving = true; renderModal();
      var before = Object.keys(pls()), star = chosen, done = false;
      var timer = setTimeout(function () {
        if (done) return;
        done = true; saving = false; renderModal(); toast(t('sp_timeout'), 'error');
      }, 20000);
      waiters.push(function (partial) {
        if (done) return true;
        if (!partial.db) return false;
        var fresh = Object.keys(pls()).filter(function (k) { return before.indexOf(k) < 0 && pls()[k] && pls()[k].spotify; })[0];
        if (!fresh) return false;
        done = true; clearTimeout(timer); closeModal();
        toast(t('sp_saved', charName(star), pls()[fresh].title || v));
        go('#/p/' + encodeURIComponent(fresh));
        return true;
      });
      // an error answer (Spotify paused meanwhile) comes as the usual toast; let the parent try again
      onCmdError = function () { if (done) return; done = true; clearTimeout(timer); saving = false; renderModal(); };
      send('PLAYLIST_NEW_SPOTIFY', { title: v, star: star });
    }
    openModal({
      autofocus: 'spname',
      render: function () {
        var other = chosen ? playlistOfChar(chosen) : null;
        return [h('h3', null, t('sp_save_title')), h('p', { class: 'small muted' }, t('sp_save_help')),
          h('label', { class: 'field' }, h('span', null, t('name')),
            h('input', { class: 'input', 'data-k': 'spname', maxlength: '100', value: name,
              oninput: function (e) { name = e.target.value; var b = document.querySelector('[data-k="spsaveok"]'); if (b) b.disabled = !name.trim() || !chosen; } })),
          h('div', { class: 'small muted', style: 'margin:12px 0 6px' }, t('sp_pick_char')),
          charGrid(chosen, null, function (id) { chosen = id; }, false),
          other ? h('div', { class: 'banner', style: 'margin-top:12px' }, t('token_moved', other.title || '—')) : null,
          h('div', { class: 'foot' }, h('button', { class: 'btn', onclick: closeModal }, t('cancel')),
            h('button', { class: 'btn primary', 'data-k': 'spsaveok', disabled: saving || !name.trim() || !chosen, onclick: save }, saving ? t('sp_saving') : t('save')))];
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
        h('div', { class: 'small muted' }, (p.star ? charName(p.star) : t('no_token')) + ' · ' + (p.spotify ? t('sp_playlist') : t('n_tracks', tracks.length) + (total ? ' · ' + fmtTotal(total) : '')))));
    if (p.spotify) {
      // a Spotify preset: it plays from Spotify, there is nothing of ours to add or sort
      return [head, h('div', { class: 'actions' },
          h('button', { class: 'btn primary', 'data-k': 'spplay', onclick: function () { send('PLAYLIST_PLAY', { playlistId: id }); } }, icon('play'), t('play'))),
        h('div', { class: 'card empty', 'data-k': 'sphelp' }, h('div', { class: 'big' }, '🎧'), h('div', null, t('sp_playlist')), h('div', { class: 'small' }, t('sp_playlist_help'))),
        h('div', { class: 'actions' }, h('button', { class: 'btn danger', onclick: function () {
          confirmBox(t('delete_playlist_q', p.title || '—'), t('delete_playlist_text'), t('delete'), true).then(function (ok) {
            if (!ok) return;
            send('PLAYLIST_DELETE', { playlistId: id });
            go('#/');
          });
        } }, icon('trash'), t('delete_playlist')))];
    }
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
    var foreign = !!foreignUid(sid), own = !!ownUid(sid);
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
          h('p', { class: 'small muted' }, foreign ? t('foreign_hint') : own ? t('own_hint')
            : sid === 'Jooki.Flat' || sid === 'Jooki.ThankYou' ? t('flat_shared_hint') : t('tokens_intro')),
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
            // a token of its own (tag, flat token) is its own character: its name IS the card's title, so the field says so
            return h('div', { class: 'physical', 'data-tag': tag },
              h('span', { class: 'badge' + (live ? ' accent' : '') }, live ? t('on_jooki') : own ? t(OWN[ownParts(sid).kind]) : t('token_n', i + 1)),
              h('input', { class: 'input grow', 'data-k': key, value: val, maxlength: '60', placeholder: own ? t('tag_name_ph') : t('token_name_ph'), 'aria-label': own ? t('tag_name_ph') : t('token_n', i + 1),
                oninput: function (e) { nameDraft[tag] = e.target.value; },
                onblur: commit, onkeydown: function (e) { if (e.key === 'Enter') { e.target.blur(); } } }),
              h('button', { class: 'icon-btn', 'aria-label': t('forget'), title: t('forget'), onclick: function () {
                confirmBox(t('forget_q'), t('forget_text'), t('forget'), true).then(function (ok) { if (ok) send('TOKEN_DELETE', { tagId: tag }); });
              } }, icon('x')));
          }),
          // a token of its own carries a picture: one of the library, or a photo (taken now, from the gallery or a computer)
          own && tags.length ? h('div', { class: 'picrow' },
            h('button', { class: 'btn primary', 'data-k': 'libpick', onclick: function () { libraryPicker(sid, tags[0]); } }, icon('sparkle'), t('lib_pick')),
            h('label', { class: 'btn', style: 'cursor:pointer' }, icon('camera'), t('photo_btn'),
              h('input', { type: 'file', accept: 'image/*', 'data-k': 'photo', style: 'display:none', onchange: function (e) {
                var f = e.target.files && e.target.files[0]; if (!f) return;
                closeModal(); tokenImageEditor(tags[0], f, sid);
              } }))) : null,
          own && tags.length && (S.db.tokens[tags[0]] || {}).image ? h('button', { class: 'btn ghost', 'data-k': 'photo-remove', style: 'color:var(--danger)',
            onclick: function () { send('TOKEN_EDIT', { tagId: tags[0], image: false }); } }, t('photo_remove')) : null,
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

  /* ------------------------------------------------------------------ the picture library */
  // Ready-made pictures for the tokens of their own (docs/23 §5): Fluent Emoji 3D (Microsoft, MIT,
  // tokimg/LICENSE.txt), 128 px WebP shipped with the page, so it works without Internet.
  // tokimg/index.json = { cats: [[id, {fr, en, nl}, iconId]], img: [[id, cat, fr, en, nl, "search words"]] }.
  // The grid is filled here, not by renderModal: typing in the search keeps the field and the scroll.
  var libIdx = null, libWait = null;
  function loadLibIndex(cb) {
    if (libIdx) return cb(libIdx);
    if (libWait) { libWait.push(cb); return; }
    libWait = [cb];
    getText('/tokimg/index.json', function (txt) {
      var d = null; try { d = JSON.parse(txt); } catch (e) {}
      if (d && Array.isArray(d.img) && Array.isArray(d.cats)) libIdx = d;
      var w = libWait; libWait = null; w.forEach(function (f) { f(libIdx); });
    });
  }
  function libName(r) { return (lang === 'en' ? r[3] : lang === 'nl' ? r[4] : r[2]) || r[2]; }
  function libraryPicker(sid, tag) {
    var q = '', failed = false, chips = {}, picked = false;
    var body = h('div', { class: 'libbody', 'data-k': 'libgrid' });
    var cats = h('div', { class: 'libcats', role: 'tablist' });
    var input = h('input', { class: 'input', type: 'search', 'data-k': 'imgq', placeholder: t('lib_search_ph'), autocomplete: 'off', 'aria-label': t('lib_search_ph'),
      oninput: function (e) { q = e.target.value; fill(); body.scrollTop = 0; } });
    function pick(r) {
      var tk = S.db.tokens[tag] || {}, p = { tagId: tag, image: 'lib:' + r[0] };
      if (!tk.name) p.name = libName(r);   // an unnamed token takes the picture's name; it can be changed
      send('TOKEN_EDIT', p);
      picked = true; closeModal(); toast(t('lib_set', libName(r))); charModal(sid);
    }
    function cell(r) {
      return h('button', { class: 'libcell', 'data-img': r[0], title: libName(r), onclick: function () { pick(r); } },
        h('img', { src: '/tokimg/' + r[0] + '.webp', alt: '', loading: 'lazy', decoding: 'async' }), h('span', null, libName(r)));
    }
    function fill() {
      body.innerHTML = '';
      if (!libIdx) { body.appendChild(h('p', { class: 'small muted libempty' }, failed ? t('lib_fail') : t('lib_loading'))); return; }
      var nq = normTxt(q.trim());
      if (nq) {
        var hits = libIdx.img.filter(function (r) { return (' ' + r[5]).indexOf(' ' + nq) >= 0 || normTxt(libName(r)).indexOf(nq) >= 0; });
        hits.sort(function (a, b) { return (normTxt(libName(a)).indexOf(nq) === 0 ? 0 : 1) - (normTxt(libName(b)).indexOf(nq) === 0 ? 0 : 1); });
        if (!hits.length) { body.appendChild(h('p', { class: 'small muted libempty' }, t('lib_none', q.trim()))); return; }
        body.appendChild(h('div', { class: 'libsec' }, t('lib_n', hits.length)));
        body.appendChild(h('div', { class: 'libgrid' }, hits.map(cell)));
        return;
      }
      libIdx.cats.forEach(function (c) {
        body.appendChild(h('div', { class: 'libsec', 'data-cat': c[0] }, c[1][lang] || c[1].fr));
        body.appendChild(h('div', { class: 'libgrid' }, libIdx.img.filter(function (r) { return r[1] === c[0]; }).map(cell)));
      });
    }
    function spy() {
      if (q.trim() || !libIdx) return;
      var cur = libIdx.cats[0][0];
      Array.prototype.forEach.call(body.querySelectorAll('[data-cat]'), function (s) { if (s.offsetTop - 12 <= body.scrollTop) cur = s.getAttribute('data-cat'); });
      Object.keys(chips).forEach(function (k) { chips[k].classList.toggle('on', k === cur); });
    }
    body.addEventListener('scroll', spy, { passive: true });
    function buildCats() {
      cats.innerHTML = '';
      (libIdx ? libIdx.cats : []).forEach(function (c, i) {
        var name = c[1][lang] || c[1].fr;
        chips[c[0]] = h('button', { class: i ? '' : 'on', title: name, 'aria-label': name, 'data-libcat': c[0], onclick: function () {
          q = ''; input.value = ''; fill();
          var s = body.querySelector('[data-cat="' + c[0] + '"]'); if (s) body.scrollTop = s.offsetTop;
          spy();
        } }, h('img', { src: '/tokimg/' + c[2] + '.webp', alt: '' }));
        cats.appendChild(chips[c[0]]);
      });
    }
    var head = h('div', { class: 'libhead' },
      h('div', { class: 'row' }, h('h3', { class: 'grow', style: 'margin:0' }, t('lib_pick')),
        h('button', { class: 'btn ghost', 'data-k': 'libcancel', onclick: function () { closeModal(); } }, t('cancel'))),
      h('div', { class: 'search' }, icon('search'), input), cats);
    openModal({ cls: 'libsheet', autofocus: null, onclose: function () { if (!picked) charModal(sid); },
      render: function () { return [head, body]; } });
    fill();
    loadLibIndex(function (d) { failed = !d; buildCats(); fill(); });
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
  function tokenImageEditor(tag, file, sid) {
    sid = sid || ('tag.' + tag);   // the sheet to go back to
    var SRC_MAX = 640, VIEW = 320, OUT = 128, R = VIEW / 2 - 6;
    var src = document.createElement('canvas'), cut = document.createElement('canvas'), sw = 0, sh = 0;
    var keep = null, undo = [], rot = 0, zoom = 1, px = 0, py = 0, tol = 25, busy = false;
    // The background is what the flood reaches from the edges without crossing a contour: a
    // pixel is taken when its colour is close to the seed's AND the picture is flat there
    // (luminance Sobel under EDGE). So a silver sword on white keeps its outline even though
    // silver is within the colour tolerance of white. Then the thin anti-aliased rim left
    // along the contour is peeled when it is close to the background colour next to it.
    var EDGE = 28, pix = null, grad = null;
    function buildGrad() {
      pix = src.getContext('2d').getImageData(0, 0, sw, sh).data;
      var L = new Float32Array(sw * sh), n = sw * sh;
      for (var i = 0; i < n; i++) L[i] = 0.299 * pix[i * 4] + 0.587 * pix[i * 4 + 1] + 0.114 * pix[i * 4 + 2];
      grad = new Uint8Array(n);
      for (var y = 1; y < sh - 1; y++) for (var x = 1; x < sw - 1; x++) {
        var j = y * sw + x;
        var gx = (L[j - sw + 1] + 2 * L[j + 1] + L[j + sw + 1]) - (L[j - sw - 1] + 2 * L[j - 1] + L[j + sw - 1]);
        var gy = (L[j + sw - 1] + 2 * L[j + sw] + L[j + sw + 1]) - (L[j - sw - 1] + 2 * L[j - sw] + L[j - sw + 1]);
        grad[j] = Math.min(255, (Math.abs(gx) + Math.abs(gy)) / 4);
      }
    }
    function dist(i, j) { var dr = pix[i * 4] - pix[j * 4], dg = pix[i * 4 + 1] - pix[j * 4 + 1], db = pix[i * 4 + 2] - pix[j * 4 + 2]; return Math.sqrt(dr * dr + dg * dg + db * db); }
    function peel(lim) {
      var n = sw * sh, changed = false;
      for (var pass = 0; pass < 2; pass++) {
        var drop = [];
        for (var i = 0; i < n; i++) {
          if (!keep[i] || grad[i] <= EDGE) continue;
          var x = i % sw, y = (i - x) / sw, nb = [x > 0 ? i - 1 : -1, x < sw - 1 ? i + 1 : -1, y > 0 ? i - sw : -1, y < sh - 1 ? i + sw : -1];
          for (var k = 0; k < 4; k++) { var j = nb[k]; if (j >= 0 && !keep[j] && dist(i, j) <= lim) { drop.push(i); break; } }
        }
        for (var q = 0; q < drop.length; q++) keep[drop[q]] = 0;
        changed = changed || drop.length > 0;
      }
      return changed;
    }
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
      var d = pix, lim = tol * 4.4, changed = false;
      seeds.forEach(function (sd) {
        var x0 = sd[0], y0 = sd[1];
        if (x0 < 0 || y0 < 0 || x0 >= sw || y0 >= sh) return;
        var i0 = (y0 * sw + x0), r0 = d[i0 * 4], g0 = d[i0 * 4 + 1], b0 = d[i0 * 4 + 2];
        if (!keep[i0]) return;
        var stack = [i0], seen = new Uint8Array(sw * sh); seen[i0] = 1;
        while (stack.length) {
          var i = stack.pop(), dr = d[i * 4] - r0, dg = d[i * 4 + 1] - g0, db = d[i * 4 + 2] - b0;
          if (grad[i] > EDGE) continue;   // a contour: the zone stops here
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
    function act(seeds) { if (!ready()) return; pushUndo(); var f = flood(seeds); if (peel(tol * 4.4 * 0.4) || f) { rebuildCut(); draw(); } else undo.pop(); }
    function removeBackground() {   // from a clean slate, so the tolerance slider is what you see
      if (!ready()) return;
      pushUndo(); keep.fill(1);
      var e = 2, mx = Math.floor(sw / 2), my = Math.floor(sh / 2);
      flood([[e, e], [sw - 1 - e, e], [e, sh - 1 - e], [sw - 1 - e, sh - 1 - e], [mx, e], [mx, sh - 1 - e], [e, my], [sw - 1 - e, my]]);
      peel(tol * 4.4 * 0.4); rebuildCut(); draw();
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
            if (now && now !== before) { clearInterval(tm); closeModal(); toast(t('saved')); charModal(sid); }
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
        h('button', { class: 'btn', onclick: function () { closeModal(); charModal(sid); } }, t('cancel')),
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
      buildGrad(); rebuildCut(); draw();
      removeBackground();   // the usual case is done at once; the tools are there to adjust
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
  // the Update page's body (Settings > Update)
  function updateCard() {
    var cur = installed();
    if (upd.state === 'running' || upd.state === 'rebooting') {
      return h('div', { class: 'card', style: 'padding:16px', 'data-k': 'updcard' },
        h('div', { class: 'row' }, h('div', { class: 'spinner', style: 'width:28px;height:28px;border-width:3px;margin:0' }),
          h('b', { class: 'grow' }, upd.state === 'rebooting' ? t('upd_rebooting') : t('upd_running'))),
        updSteps(),
        h('p', { class: 'small muted' }, t('upd_keep')));
    }
    var avail = upd.state === 'checked' && updateAvailable();
    var bad = upd.state === 'failed' || upd.state === 'offline';
    var look = avail ? ['up', 'accent'] : bad ? ['x', 'danger'] : upd.state === 'checked' ? ['check', 'ok'] : ['up', 'muted'];
    var title = upd.state === 'checking' ? t('upd_checking') : upd.state === 'offline' ? t('upd_offline') : upd.state === 'failed' ? t('upd_failed')
      : avail ? t('upd_available', upd.latest) : upd.state === 'checked' ? t('upd_uptodate') : 'OpenJooki ' + (cur || '—');
    return [
      h('div', { class: 'statuscard', 'data-k': 'updcard' }, h('div', { class: 'bigico ' + look[1] }, icon(look[0])),
        h('b', null, title), h('p', null, avail ? t('upd_text') : 'OpenJooki ' + (cur || '—'))),
      avail ? h('button', { class: 'btn primary block', 'data-k': 'updnow', onclick: startUpdate }, icon('upload'), t('upd_now'))
        : h('button', { class: 'btn block', 'data-k': 'updcheck', disabled: upd.state === 'checking' || !cur, onclick: checkUpdate }, t('upd_check'))
    ];
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

  /* ---------------- settings: a short page; each topic opens on a page of its own (#/settings/<topic>) */
  // A row: icon tile, label (+ a small line), then a value and a chevron, or a switch.
  function sRow(o) {
    var right = [];
    if (o.value !== undefined && o.value !== null && o.value !== '') right.push(h('span', { class: 'val' + (o.vcls ? ' ' + o.vcls : '') }, o.value));
    if (o.sw) right.push(h('input', { type: 'checkbox', role: 'switch', class: 'sw', checked: !!o.on, 'data-k': o.k, 'aria-label': o.label, onchange: o.onchange }));
    if (o.check) right.push(h('span', { class: 'tick' }, icon('check')));
    if (o.href || (o.onclick && !o.nochev)) right.push(h('span', { class: 'chev' }, icon('chev')));
    var inner = [o.icon ? h('span', { class: 'ico ' + (o.color || 'gray') }, icon(o.icon)) : null,
      h('span', { class: 'lbl' }, h('span', { class: 'l1' }, o.label), o.sub ? h('span', { class: 'l2' }, o.sub) : null), right];
    var cls = 'srow' + (o.icon ? '' : ' noico') + (o.danger ? ' danger' : '');
    if (o.sw) return h('label', { class: cls }, inner);
    if (o.href) return h('a', { class: cls, href: o.href, 'data-k': o.k }, inner);
    if (o.onclick) return h('button', { class: cls, type: 'button', 'data-k': o.k, lang: o.lang || null, disabled: o.disabled ? 'disabled' : null, onclick: o.onclick }, inner);
    return h('div', { class: cls, 'data-k': o.k }, inner);
  }
  function sGroup(title, rows, foot, k) {
    return [title ? h('div', { class: 'gtitle' }, title) : null, h('div', { class: 'group', 'data-k': k }, rows),
      foot ? h('div', { class: 'gfoot' }, foot) : null];
  }
  function stat(ic, label, value, sub, subCls, meter, meterCls, k) {
    return h('div', { class: 'stat', 'data-k': k },
      h('div', { class: 'k' }, icon(ic), h('span', { class: 'ellipsis' }, label)),
      h('div', { class: 'v ellipsis' }, value),
      sub ? h('div', { class: 's ellipsis' + (subCls ? ' ' + subCls : '') }, sub) : null,
      meter !== null && meter !== undefined ? h('div', { class: 'minibar' }, h('i', { class: meterCls || '', style: 'width:' + Math.max(0, Math.min(100, meter)) + '%' })) : null);
  }
  var SUBS = { bluetooth: 's_bt', night: 'night_mode', airplane: 'air_title', wifi: 'wifi', update: 's_update', language: 'language',
               parent: 'parent_label', home: 's_home', maintenance: 's_maint', theme: 's_theme', mp3: 's_mp3' };
  function settingsPage(sub) {
    var body = sub === 'bluetooth' ? btPage() : sub === 'night' ? nightPage() : sub === 'airplane' ? airPage() : sub === 'wifi' ? wifiPage()
      : sub === 'update' ? updateCard() : sub === 'language' ? langPage() : sub === 'parent' ? parentPage() : sub === 'home' ? homePage()
      : sub === 'maintenance' ? maintPage() : sub === 'theme' ? themePage() : sub === 'mp3' ? mp3Page() : null;
    return body ? h('div', { class: 'settings sub' }, body) : viewSettings();
  }
  function viewSettings() {
    var d = S.device, pw = S.power, w = S.wifi, cfg = S.audio.config, m = obj(S.maintenance), b = obj(S.bluetooth), c = S.bedtime.cfg;
    var lvl = pw.level && typeof pw.level === 'object' ? Number(pw.level.p) : NaN;
    var known = !(isNaN(lvl) || (lvl === 0 && pw.level && !pw.level.mv)), pct = known ? Math.round(lvl / 10) : null;
    var du = obj(d.diskUsage);
    var total = Number(du.total) * 1024, used = Number(du.used) * 1024, free = Number(du.available) * 1024;
    var avail = upd.state === 'checked' && updateAvailable();
    var name = (d.hostname || '—').replace(/\.local$/, '');
    var con = obj(b.connected);
    var hero = h('div', { class: 'hero' },
      h('div', { class: 'row' }, h('div', { class: 'avatar', 'aria-hidden': 'true' }, 'J'),
        h('div', { class: 'grow', style: 'min-width:0' }, h('div', { class: 'hname ellipsis' }, name),
          h('div', { class: 'hsub ellipsis' }, h('i', { class: 'dot' + (online ? ' on' : '') }), (online ? t('connected') : t('offline')) + (w.ssid ? ' · ' + w.ssid : ''))),
        d.core ? h('button', { class: 'pillbtn', 'data-k': 'rename', onclick: nameModal }, t('rename')) : null),
      h('div', { class: 'stats' },
        stat('bat', t('battery'), known ? pct + ' %' : '—', pw.charging ? t('charging') : pw.connected ? t('plugged') : null, null, known ? pct : null, pct !== null && pct < 20 ? 'low' : 'ok'),
        stat('disk', t('storage'), total ? fmtBytes(free) : '—', total ? t('s_storage_free') : null, null, total ? used / total * 100 : null),
        stat('tag', t('version'), d.openjooki || '—', avail ? t('s_avail', upd.latest) : upd.state === 'checked' ? t('s_uptodate') : null, avail ? 'accent-text' : 'ok-text', null, null, 'version')));
    return h('div', { class: 'settings' }, hero,
      avail ? sGroup(null, [sRow({ icon: 'up', color: 'orange', label: t('upd_banner', upd.latest), value: t('upd_see'), vcls: 'acc', href: '#/settings/update', k: 'updrow' })]) : null,
      sGroup(t('s_listen'), [
        sRow({ icon: 'vol', color: 'orange', label: t('toy_safe'), sw: true, on: d.toy_safe, k: 'toysafe', onchange: function (e) { send('SET_TOY_SAFE', { enable: e.target.checked }); } }),
        sRow({ icon: 'shuffle', color: 'indigo', label: t('shuffle'), sw: true, on: cfg.shuffle_mode, k: 'shuffle', onchange: function (e) { send('SET_CFG', { shuffle_mode: e.target.checked }); } }),
        sRow({ icon: 'repeat', color: 'indigo', label: t('repeat'), sw: true, on: cfg.repeat_mode === 1 || cfg.repeat_mode === true, k: 'repeat', onchange: function (e) { send('SET_CFG', { repeat_mode: e.target.checked ? 1 : 0 }); } }),
        canConvert() ? sRow({ icon: 'note', color: 'teal', label: t('s_mp3'), sub: t('s_mp3_sub'), value: mp3Kbps() + ' kbps', href: '#/settings/mp3', k: 'mp3nav' }) : null,
        typeof b.state === 'number' ? sRow({ icon: 'bt', color: 'blue', label: t('s_bt'), value: con.mac ? (con.name || t('bt_unnamed')) : t('s_none'), href: '#/settings/bluetooth', k: 'btrow' }) : null
      ]),
      c.start !== undefined || d.airplane !== undefined ? sGroup(t('s_night_trip'), [
        c.start !== undefined ? sRow({ icon: 'moon', color: 'indigo', label: t('night_mode'), value: c.enabled ? hm(c.start) + ' – ' + hm(c.stop) : t('s_off'), href: '#/settings/night', k: 'nightrow' }) : null,
        d.airplane !== undefined ? sRow({ icon: 'plane', color: 'orange', label: t('air_title'), value: t('s_off'), href: '#/settings/airplane', k: 'airrow' }) : null
      ]) : null,
      sGroup(t('s_general'), [
        sRow({ icon: 'wifi', color: 'blue', label: t('wifi'), value: w.ssid || '—', href: '#/settings/wifi', k: 'wifinav' }),
        sRow({ icon: 'up', color: 'green', label: t('s_update'), value: avail ? t('s_avail', upd.latest) : upd.state === 'checked' ? t('s_uptodate') : '', vcls: avail ? 'acc' : 'good', href: '#/settings/update', k: 'updnav' }),
        sRow({ icon: 'globe', color: 'teal', label: t('language'), value: (LANGS.filter(function (l) { return l[0] === lang; })[0] || ['', ''])[1], href: '#/settings/language', k: 'langnav' }),
        sRow({ icon: 'contrast', color: 'gray', label: t('s_theme'), value: t('s_theme_' + theme), href: '#/settings/theme', k: 'themenav' }),
        d.core ? sRow({ icon: 'sparkle', color: 'party', label: t('s_party'), sub: t('s_party_sub'), nochev: true, k: 'party', onclick: function () {
          if (send('OJ_PARTY', {}) !== false) toast(t('s_party_done'));
        } }) : null
      ]),
      typeof m.parent === 'boolean' ? sGroup(t('s_parents'), [
        sRow({ icon: 'lock', color: 'red', label: t('parent_label'), value: m.parent ? t('s_on') : t('s_off'), href: '#/settings/parent', k: 'parentnav' })
      ], t('s_parent_foot')) : null,
      typeof m.ssh === 'boolean' ? sGroup(t('s_advanced'), [
        sRow({ icon: 'home', color: 'gray', label: t('s_home'), sub: t('s_home_sub'), value: m.mqtt_lan ? t('s_on') : t('s_off'), href: '#/settings/home', k: 'homenav' }),
        sRow({ icon: 'wrench', color: 'gray', label: t('s_maint'), sub: t('s_maint_sub'), value: m.ssh ? t('s_open') : t('s_closed'), href: '#/settings/maintenance', k: 'maintnav' })
      ]) : null,
      sGroup(null, [sRow({ icon: 'power', color: 'red', label: t('power_off'), danger: true, nochev: true, k: 'poweroff', onclick: function () {
        confirmBox(t('power_off_q'), t('power_off_text'), t('power_off'), true).then(function (ok) {
          if (!ok) return;
          send('SHUTDOWN', { src: 'from-web' }); toast(t('power_off_done'));
        });
      } })]),
      h('div', { class: 'verline', 'data-k': 'verline' }, 'OpenJooki ' + (d.openjooki || '—') + ' · ' + t('web_page') + ' ' + VERSION + (d.firmware ? ' · ' + d.firmware : '')));
  }
  function langPage() {
    return sGroup(null, LANGS.map(function (l) {
      return sRow({ label: l[1], lang: l[0], check: lang === l[0], nochev: true, k: 'lang-' + l[0], onclick: function () { setLang(l[0]); } });
    }), t('s_lang_foot'));
  }
  // the MP3 quality for FLAC / WAV sent to the Jooki, kept on this phone or computer
  function mp3Page() {
    return sGroup(null, MP3_RATES.map(function (v) {
      return sRow({ label: t('s_mp3_' + v), check: mp3Kbps() === v, nochev: true, k: 'mp3-' + v, onclick: function () { lsSet('oj.mp3', String(v)); render(); } });
    }), t('s_mp3_foot'));
  }
  function themePage() {
    return sGroup(null, THEMES.map(function (v) {
      return sRow({ label: t('s_theme_' + v), check: theme === v, nochev: true, k: 'theme-' + v, onclick: function () { setTheme(v); } });
    }), t('s_theme_foot'));
  }
  // Bluetooth speaker or headphones (docs/26), only on a core that offers it. The ESP32 plays to the
  // speaker by itself once connected, and reconnects to it when it comes back.
  var btTried = null;   // the device this page asked to connect, to tell a failure from "nothing connected"
  function btPage() {
    var b = obj(S.bluetooth);
    if (typeof b.state !== 'number') return null;
    var st = b.state, devs = arr(b.devices), con = obj(b.connected);
    function name(d) { return d.name || t('bt_unnamed'); }
    if (arr(S.device.flags).indexOf('BT_OFF') >= 0) return h('div', { class: 'gfoot', 'data-k': 'btair' }, t('bt_air'));
    if (con.mac) {
      btTried = null;
      return [h('div', { class: 'statuscard', 'data-k': 'btcard' }, h('div', { class: 'bigico blue' }, icon('bt')),
          h('b', { 'data-k': 'bton' }, t('bt_on', name(con))), h('p', null, t('bt_on_help'))),
        sGroup(null, [sRow({ label: t('bt_off_btn'), danger: true, nochev: true, k: 'btforget', onclick: function () {
          confirmBox(t('bt_off_q'), t('bt_off_text'), t('bt_off_btn'), false).then(function (ok) { if (ok) send('OJ_BT_FORGET', { mac: con.mac }); });
        } })])];
    }
    // the speakers the Jooki already knows: reconnecting needs no pairing mode, and a paired
    // speaker does not show in a search, so they come first, whatever the search finds
    var known = arr(b.known).map(function (k) { return Object.assign({ known: true }, k); });
    devs = known.concat(devs.filter(function (d) { return !known.some(function (k) { return k.mac === d.mac; }); }));
    var rows = devs.map(function (d) {
      var busy = st === 4 && btTried === d.mac;
      return sRow({ label: name(d), sub: d.known ? t('bt_known') : null, value: busy ? t('bt_connecting') : t('bt_connect'), vcls: 'acc', nochev: true,
        k: 'btdev-' + d.mac, disabled: st === 4, onclick: function () { if (send('OJ_BT_CONNECT', { mac: d.mac }) !== false) { btTried = d.mac; } } });
    });
    return h('div', { 'data-k': 'btcard' },
      rows.length ? sGroup(null, rows) : null,
      st === 6 && btTried ? h('p', { class: 'gfoot accent-text', 'data-k': 'btfail' }, t('bt_failed'))
        : st === 2 && !devs.length ? h('p', { class: 'gfoot', 'data-k': 'btnone' }, t('bt_none')) : null,
      h('button', { class: 'btn block', 'data-k': 'btscan', disabled: st === 1 || st === 4 ? 'disabled' : null,
        onclick: function () { btTried = null; send('OJ_BT_SCAN', {}); } }, icon('search'), st === 1 ? t('bt_searching') : t('bt_search')),
      h('p', { class: 'gfoot' }, t('bt_help')));
  }
  // Airplane mode (docs/24), only on a core that offers it. Always bounded: the Jooki switches its
  // radios back on by itself at the chosen time, and in any case at its next start.
  var airChoice = '2';   // hours, or 'morning' (the night mode's end) or 'boot'
  function airPage() {
    if (S.device.airplane === undefined) return null;
    var stop = Number(S.bedtime.cfg.stop); if (isNaN(stop)) stop = 420;
    var now = new Date(), nowMin = now.getHours() * 60 + now.getMinutes();
    var toMorning = (stop - nowMin + 1440) % 1440;
    if (toMorning < 15) toMorning += 1440;
    if (toMorning > 1440) toMorning = 1440;
    var opts = [['1', t('air_h', 1)], ['2', t('air_h', 2)], ['4', t('air_h', 4)], ['8', t('air_h', 8)], ['morning', t('air_morning', hm(stop))], ['boot', t('air_boot')]];
    function go() {
      var minutes = airChoice === 'boot' ? null : airChoice === 'morning' ? toMorning : Number(airChoice) * 60;
      var a = { sent: Date.now(), ends: minutes ? Date.now() + minutes * 60000 : 0 };
      confirmBox(t('air_q'), t('air_text', airplaneWhen(a)), t('air_btn'), true).then(function (ok) {
        if (!ok) return;
        a.sent = Date.now();
        if (send('OJ_AIRPLANE', minutes ? { minutes: minutes } : {}) !== false) { setAirplane(a); toast(t('air_sent')); }
      });
    }
    return [h('p', { class: 'gfoot', style: 'margin:0 16px 14px' }, t('air_help')),
      sGroup(t('s_air_for'), [h('div', { class: 'choice', role: 'group', 'aria-label': t('s_air_for') }, opts.map(function (o) {
        return h('button', { class: airChoice === o[0] ? 'on' : '', 'data-k': 'air-' + o[0], 'aria-pressed': String(airChoice === o[0]),
          onclick: function () { airChoice = o[0]; render(); } }, o[1]);
      }))]),
      h('button', { class: 'btn primary block', 'data-k': 'airgo', onclick: go }, icon('plane'), t('air_btn'))];
  }
  // Security switches (docs/adr/0007): only shown on a core that offers them.
  function parentPage() {
    var m = obj(S.maintenance);
    if (typeof m.parent !== 'boolean') return null;
    var rows = [sRow({ icon: 'lock', color: 'red', label: t('parent_label'), sw: true, on: m.parent, k: 'parent',
      onchange: function (e) { e.target.checked = !!m.parent; parentModal(m.parent ? 'off' : 'set'); } })];
    if (m.parent) rows.push(sRow({ label: t('parent_change'), k: 'pchange', onclick: function () { parentModal('change'); } }));
    return sGroup(null, rows, [t('parent_help'), m.parent ? ' ' + t('parent_reset') : null]);
  }
  function homePage() {
    var m = obj(S.maintenance);
    if (typeof m.ssh !== 'boolean' && typeof m.parent !== 'boolean') return null;
    var out = [sGroup(null, [sRow({ icon: 'home', color: 'gray', label: t('mqtt_label'), sw: true, on: m.mqtt_lan, k: 'mqttlan',
      onchange: function (e) { send('OJ_MQTT_LAN', { on: e.target.checked }); } })], t('mqtt_help'))];
    if (m.mqtt_lan) {
      var host = (S.net && S.net.name ? String(S.net.name) : null) || (S.device && S.device.hostname) || location.hostname;
      out.push(sGroup(t('s_connect_info'), [
        sRow({ label: t('mqtt_host_l'), value: host }), sRow({ label: t('mqtt_port_l'), value: '1883' }), sRow({ label: t('mqtt_user_l'), value: 'jooki' }),
        h('div', { class: 'srow noico col' }, h('span', { class: 'l1' }, t('mqtt_pass_l')), h('span', { class: 'mono' }, CFG.mqttPass || '—'))]));
    }
    return out;
  }
  function maintPage() {
    var m = obj(S.maintenance);
    if (typeof m.ssh !== 'boolean') return null;
    var out = [sGroup(null, [sRow({ icon: 'wrench', color: 'gray', label: t('ssh_label'), sw: true, on: m.ssh, k: 'ssh',
      onchange: function (e) { send(e.target.checked ? 'OJ_SSH_ON' : 'OJ_SSH_OFF', {}); } })], t('ssh_help'))];
    // while the access is open: a public key, kept on the Jooki across updates
    if (m.ssh) out.push(sGroup(t('ssh_key_l') + ' · ' + t('ssh_keys_n', Number(m.ssh_keys) || 0), [h('div', { class: 'gpad' },
      h('textarea', { class: 'input', rows: '3', 'data-k': 'sshkey', spellcheck: 'false', autocomplete: 'off', 'aria-label': t('ssh_key_l'), style: 'font-family:monospace;font-size:12px',
        oninput: function (e) { ui.sshKey = e.target.value; } }, ui.sshKey || ''),
      h('div', { class: 'row', style: 'gap:8px;flex-wrap:wrap;margin-top:8px' },
        h('button', { class: 'btn primary', 'data-k': 'sshkeyadd', onclick: function () {
          var k = String(ui.sshKey || '').trim();
          if (!k) return;
          var before = Number(m.ssh_keys) || 0, done = false;
          waiters.push(function (partial) {
            if (done) return true;
            if (!partial.maintenance || !(Number(obj(S.maintenance).ssh_keys) > before || before >= 5)) return false;
            done = true; ui.sshKey = ''; toast(t('ssh_key_added')); render(); return true;
          });
          onCmdError = function () { done = true; };     // refused: the usual error toast says why
          send('OJ_SSH_KEY', { key: k });
        } }, t('ssh_key_add')),
        Number(m.ssh_keys) ? h('button', { class: 'btn ghost', 'data-k': 'sshkeyclear', onclick: function () { send('OJ_SSH_KEY', { clear: true }); } }, t('ssh_key_clear')) : null))],
      t('ssh_key_help')));
    return out;
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
  function wifiPage() {
    var w = S.wifi, d = S.device, n = S.net, dbm = Number(w.signal);
    var has = w.signal !== undefined && w.signal !== null && !isNaN(dbm);
    var q = !has ? null : dbm >= -65 ? 'good' : dbm >= -75 ? 'fair' : 'weak';
    var drops = Number(n.drops) || 0, bars = h('span', { class: 'bars' });
    for (var i = 1; i <= 4; i++) bars.appendChild(h('i', { class: has && i <= (dbm >= -60 ? 4 : dbm >= -67 ? 3 : dbm >= -75 ? 2 : 1) ? 'on ' + q : null, style: 'height:' + (3 + i * 2.6) + 'px' }));
    return [h('div', { 'data-k': 'wifirow' }, sGroup(null, [
        sRow({ label: t('s_wifi_net'), value: w.ssid || '—' }),
        has ? h('div', { class: 'srow noico' }, h('span', { class: 'lbl' }, h('span', { class: 'l1' }, t('s_wifi_signal'))),
          h('span', { class: 'val wifi-' + q, 'data-k': 'wifiq' }, bars, t('wifi_' + q) + ' · ' + dbm + ' dBm')) : null,
        sRow({ label: t('s_wifi_drops'), value: String(drops) }),
        sRow({ label: t('ip'), value: d.ip || location.hostname }),
        n.name ? sRow({ label: t('s_wifi_page'), value: String(n.name) }) : null
      ], q === 'weak' ? t('wifi_advice') : null)),
      sGroup(t('s_wifi_change'), [h('a', { class: 'srow noico', href: WIFI_PAGE, target: '_blank', rel: 'noopener' },
        h('span', { class: 'lbl' }, h('span', { class: 'l1' }, 'Bluetooth')), h('span', { class: 'chev' }, icon('chev')))], wifiBluetoothLine())];
  }
  // The way back when the Jooki loses its network (docs/wifi.html, over Bluetooth): said here, while
  // the page can still be read, with the name the Jooki shows in a Bluetooth list (JOOKI2_ + its id).
  var WIFI_PAGE = 'https://guillain-rdcde.github.io/OpenJooki/wifi.html';
  function wifiBluetoothLine() {
    var id = String((S.device && S.device.id) || '');
    if (!id) return null;
    var bt = 'JOOKI2_' + id.replace(/^jooki2[-_]/i, '').toUpperCase();
    return h('span', { 'data-k': 'wifibt' }, t('wifi_bt'),
      h('a', { href: WIFI_PAGE, target: '_blank', rel: 'noopener' }, 'guillain-rdcde.github.io/OpenJooki/wifi'), ' ', t('wifi_bt_name', bt));
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
  function nightPage() {
    var c = S.bedtime.cfg;
    if (c.start === undefined) return null; // firmware without bedtime
    var mv = nightVolDrag !== null ? nightVolDrag : Number(c.maxvol) || 100;
    var timers = [0, 10, 15, 20, 30, 45, 60];
    if (timers.indexOf(Number(c.timer)) < 0) { timers.push(Number(c.timer)); timers.sort(function (a, b) { return a - b; }); }
    function volLabel(v) { return v >= 100 ? t('night_nolimit') : v + ' %'; }
    var out = [sGroup(null, [sRow({ icon: 'moon', color: 'indigo', label: t('night_mode'), sw: true, on: c.enabled, k: 'nighton',
      onchange: function (e) { setBedtime({ enabled: e.target.checked }); } })], t('night_help'), 'bedcard')];
    if (!c.enabled) return out;
    out.push(sGroup(t('s_night_hours'), [
      h('div', { class: 'srow noico', 'data-k': 'nightstatus' }, S.bedtime.night ? h('b', { class: 'accent-text' }, t('night_now')) : h('span', { class: 'muted' }, t('night_next', hm(c.start)))),
      h('div', { class: 'timepair' },
        h('label', { class: 'field' }, h('span', null, t('night_from')), h('input', { class: 'input', type: 'time', value: hm(c.start), 'data-k': 'nightstart',
          onchange: function (e) { if (e.target.value) setBedtime({ start: e.target.value }); } })),
        h('label', { class: 'field' }, h('span', null, t('night_to')), h('input', { class: 'input', type: 'time', value: hm(c.stop), 'data-k': 'nightstop',
          onchange: function (e) { if (e.target.value) setBedtime({ stop: e.target.value }); } })))
    ], t('night_clock')));
    out.push(sGroup(t('s_night_during'), [
      h('label', { class: 'srow noico' }, h('span', { class: 'lbl' }, h('span', { class: 'l1' }, t('night_timer'))),
        h('select', { class: 'input mini', 'data-k': 'nighttimer', onchange: function (e) { e.target.blur(); setBedtime({ timer: Number(e.target.value) }); } },
          timers.map(function (m) { return h('option', { value: String(m), selected: Number(c.timer) === m ? 'selected' : null }, m ? t('sleep_min', m) : t('night_timer_none')); }))),
      h('label', { class: 'srow noico col' }, h('span', { class: 'row', style: 'width:100%' }, h('span', { class: 'l1 grow' }, t('night_maxvol')),
          h('span', { class: 'val', 'data-nightvol': '1' }, volLabel(mv))),
        h('input', { class: 'range', type: 'range', min: '10', max: '100', step: '5', value: String(mv), 'data-k': 'nightvol', 'aria-label': t('night_maxvol'),
          oninput: function (e) { nightVolDrag = Number(e.target.value); var l = document.querySelector('[data-nightvol]'); if (l) l.textContent = volLabel(nightVolDrag); },
          onchange: function (e) { nightVolDrag = null; setBedtime({ maxvol: Number(e.target.value) }); } })),
      sRow({ label: t('night_dim'), sw: true, on: c.dim, k: 'nightdim', onchange: function (e) { setBedtime({ dim: e.target.checked }); } })
    ]));
    return out;
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
  // Spotify started from the phone has no playlist of ours, and its title may arrive a moment later
  function isSpotify() { var np = S.audio.nowPlaying; return !!(np && (np.service === 'SPOTIFY' || np.service === 'DEEZER')); }
  function hasNow() { var np = S.audio.nowPlaying; return !!(np && ((np.playlistId && np.uri) || isSpotify())); }
  function nowTitle() {
    var np = S.audio.nowPlaying;
    if (isSpotify()) return cleanTitle(np.track) || (np.service === 'DEEZER' ? 'Deezer' : 'Spotify');
    return cleanTitle(np.track || trackTitle(np.trackId));
  }
  // under the title: for Spotify "artist / album" (the album, else what it plays from), else our playlist's name
  function nowSource(pl) {
    var np = S.audio.nowPlaying;
    if (isSpotify()) return [np.artist, np.album || np.source].filter(function (x) { return x && x !== 'unknown'; }).join(' / ');
    return np.source || (pl && pl.title) || '';
  }
  function curPos() {
    var pb = S.audio.playback;
    var p = Number(pb.position_ms) || 0;
    if (pb.state === 'PLAYING') p += Date.now() - posStamp;
    var d = Number(S.audio.nowPlaying.duration_ms) || 0;
    return d ? Math.min(p, d) : p;
  }
  // The cover of what plays. Spotify's daemon gives "spotify:image:<id>" or an address on Spotify's
  // image servers: the phone loads it from there (the page's CSP allows *.scdn.co and
  // *.spotifycdn.com), never through the Jooki. Local music keeps its /artwork/ file.
  function coverSrc(u) {
    u = String(u || '');
    var m = /^spotify:image:([0-9a-f]{16,64})$/i.exec(u);
    return m ? 'https://i.scdn.co/image/' + m[1] : u;
  }
  function playerBar() {
    var np = S.audio.nowPlaying;
    var pl = pls()[np.playlistId];
    var now = hasNow();
    var cover = h('div', { class: 'cover' });
    var fallback = function () { return now && pl && pl.star ? tokVisual(pl.star, 'sm') : icon('note'); };
    if (now && np.image) {
      var ci = h('img', { src: coverSrc(np.image), alt: '' });
      ci.onerror = function () { ci.replaceWith(fallback()); };
      cover.appendChild(ci);
    } else cover.appendChild(fallback());
    var d = Number(np.duration_ms) || 0;
    return h('div', { class: 'player' + (now ? '' : ' idle'), 'data-k': 'player' },
      h('div', { class: 'prog' }, h('i', { 'data-prog': '1', style: 'width:' + (d ? Math.round(curPos() / d * 100) : 0) + '%' })),
      cover,
      h('div', { class: 'info', role: 'button', tabindex: '0', 'aria-label': t('open_player'), onclick: function () { if (now) nowPlayingModal(); },
        onkeydown: function (e) { if (e.key === 'Enter' && now) nowPlayingModal(); } },
        h('div', { class: 't ellipsis' }, now ? nowTitle() : t('nothing_playing')),
        h('div', { class: 's ellipsis' }, sleepInfo() ? h('span', { class: 'sleepmini' }, icon('moon'), h('span', { 'data-sleep-short': '1' }, sleepShort())) : null,
          now ? nowSource(pl) : t('nothing_hint'))),
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
        return [np.playlistId, np.trackId, np.trackIndex, np.service, np.track, np.image, S.audio.playback.state, c.volume, c.shuffle_mode, c.repeat_mode, np.duration_ms, sl.mode, sl.total, sl.auto].join('|');
      },
      render: function () {
        var np = S.audio.nowPlaying, pl = pls()[np.playlistId];
        var cfg = S.audio.config;
        var d = Number(np.duration_ms) || 0;
        var stream = np.service === 'STREAM';
        var art = h('div', { class: 'art' });
        if (np.image) {
          var ai = h('img', { src: coverSrc(np.image), alt: '' });
          ai.onerror = function () { ai.replaceWith(tokVisual(pl && pl.star, '')); };
          art.appendChild(ai);
        } else art.appendChild(tokVisual(pl && pl.star, ''));
        var vol = volDrag !== null ? volDrag : Number(cfg.volume) || 0;
        return h('div', { class: 'np' }, art,
          h('div', { class: 't' }, nowTitle() || '—'),
          h('div', { class: 'muted' }, isSpotify() ? nowSource(pl) : [np.artist && np.artist !== 'unknown' ? np.artist : null, np.source || (pl && pl.title)].filter(Boolean).join(' · ')),
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
          // Spotify started from the phone: offer to put it on a character
          np.service === 'SPOTIFY' && !np.playlistId ? h('div', { class: 'actions', style: 'justify-content:center;margin-top:12px' },
            h('button', { class: 'btn primary', 'data-k': 'spsave', onclick: spotifySaveModal }, icon('plus'), t('sp_save'))) : null,
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
    // an airplane mode asked from this browser: the Jooki is away on purpose (and if it is still
    // here half a minute later, the request did not go through: forget it)
    if (online && gotState && airplane && Date.now() - airplane.sent > 30000) setAirplane(null);
    var air = !online ? airplaneNow() : null;
    if (!gotState) {
      body = h('div', { class: 'connect-screen' }, h('div', { class: 'spinner' }),
        h('div', null, air ? t('air_title') : online || !everOnline ? t('connecting') : t('offline')),
        air ? h('p', { class: 'small muted' }, t('air_offline', airplaneWhen(air))) : !online && retryDelay > 1600 ? h('p', { class: 'small muted' }, t('offline_long')) : null,
        !online && retryDelay > 1600 ? h('button', { class: 'btn', onclick: function () { retryDelay = 1000; connect(); } }, t('retry')) : null);
      title = t('my_jooki');
    } else if (r.name === 'p') {
      var p = pls()[r.arg];
      title = p ? (p.title || '—') : t('playlists');
      back = '#/';
      body = viewPlaylist(r.arg);
    } else if (r.name === 'tokens') { title = t('tokens'); body = viewTokens(); }
    else if (r.name === 'library') { title = t('library'); body = viewLibrary(r.arg); }
    else if (r.name === 'settings') {
      var sub = r.arg && SUBS[r.arg] ? r.arg : null;
      title = sub ? t(SUBS[sub]) : t('settings');
      if (sub) back = '#/settings';
      body = sub ? settingsPage(sub) : viewSettings();
    }
    else { title = t('playlists'); body = viewPlaylists(); }
    document.title = gotState ? title + ' — OpenJooki' : 'OpenJooki';
    var conn = h('div', { class: 'conn ' + (online ? 'on' : 'off'), role: 'status', 'aria-live': 'polite' }, h('i'), online ? t('connected') : t('offline'));
    var shell = h('div', { class: 'shell' },
      h('header', { class: 'topbar' },
        back ? h('a', { class: 'icon-btn', href: back, 'aria-label': t('back') }, icon('back')) : h('div', { class: 'brand' }, h('div', { class: 'dot' }, 'J')),
        h('div', { class: 'titles' },
          h('a', { class: 'wordmark', href: '#/', 'aria-label': 'OpenJooki' }, 'Open', h('span', null, 'Jooki')),
          h('h1', null, title)), conn),
      !online && gotState ? h('div', { class: 'banner' + (air ? '' : ' danger'), style: 'margin:12px 16px 0' }, air ? t('air_offline', airplaneWhen(air)) : t('offline_long')) : null,
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
