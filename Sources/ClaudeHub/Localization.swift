import Foundation

enum AppLanguage: String, CaseIterable {
    case tr
    case en
    case fr
    case es

    static func resolve(_ preferredLanguages: [String]) -> AppLanguage {
        for identifier in preferredLanguages {
            let code = identifier
                .lowercased()
                .components(separatedBy: CharacterSet(charactersIn: "-_"))
                .first ?? ""
            if let language = AppLanguage(rawValue: code) {
                return language
            }
        }
        return .en
    }

    var locale: Locale { Locale(identifier: rawValue) }
}

enum L10nKey {
    case noAccounts, refreshNow, accounts, quit, loading, error
    case fiveHour, sevenDay, sevenDaySonnet, sevenDayOpus, oauthApps, cowork, updated
    case addProfile, removeAccount, pickerTitle, select
    case missingClaudeJSON, profileAlreadyAdded
    case accountName, accountNameHelp, add, cancel, accountNameEmpty, defaultAccountLabel
    case usageUsed, extraUsageWithLimit, extraUsage
    case resetDaysHours, resetHours, resetMinutes
    case keychainReadFailed, malformedCredential
    case missingRefreshToken, missingScopes, cliNotFound, loginRefreshFailed
    case invalidAnthropicResponse, anthropicHTTPFailed
    case accountStoreUnavailable
    case sessionExpired, refreshTokenExpiring
    case confirmRemoveAccount, removeAccountHelp
}

enum L10n {
    static var language: AppLanguage {
        AppLanguage.resolve(Locale.preferredLanguages)
    }

    static func text(_ key: L10nKey, language: AppLanguage? = nil) -> String {
        let selected = language ?? self.language
        return translations[selected]?[key] ?? translations[.en]![key]!
    }

    static func format(
        _ key: L10nKey,
        _ arguments: CVarArg...,
        language: AppLanguage? = nil
    ) -> String {
        let selected = language ?? self.language
        return String(
            format: text(key, language: selected),
            locale: selected.locale,
            arguments: arguments
        )
    }

    private static let translations: [AppLanguage: [L10nKey: String]] = [
        .tr: [
            .confirmRemoveAccount: "%@ kaldırılsın mı?",
            .removeAccountHelp: "Hesap ClaudeHub'dan kaldırılacak. Claude Code profil klasörü ve oturumu silinmez.",
            .sessionExpired: "Oturum süresi doldu. Bu profilin CLAUDE_CONFIG_DIR değeriyle claude auth login çalıştır, ardından yeniden bağla.",
            .refreshTokenExpiring: "Oturum yenileme süresi dolmak üzere veya doldu. Bu profil için tekrar giriş yap.",
            .accountStoreUnavailable: "Hesap dosyası okunamadı veya kaydedilemedi. Mevcut dosya korundu; bozuk JSON için .bak yedeği oluşturulmaya çalışıldı. accounts.json dosyasını kontrol edip uygulamayı yeniden aç. Hesap değişiklikleri devre dışı.",
            .noAccounts: "Henüz hesap eklenmedi",
            .refreshNow: "Şimdi yenile",
            .accounts: "Hesaplar",
            .quit: "ClaudeHub'dan çık",
            .loading: "Yükleniyor…",
            .error: "Hata: %@",
            .fiveHour: "5 saat",
            .sevenDay: "7 gün",
            .sevenDaySonnet: "7 gün Sonnet",
            .sevenDayOpus: "7 gün Opus",
            .oauthApps: "OAuth uygulamaları",
            .cowork: "Cowork",
            .updated: "Güncellendi: %@",
            .addProfile: "Mevcut Claude profilini ekle…",
            .removeAccount: "Hesap kaldır",
            .pickerTitle: "Claude Code profil klasörünü seç",
            .select: "Seç",
            .missingClaudeJSON: "Bu klasörde .claude.json bulunamadı. Önce bu CLAUDE_CONFIG_DIR ile Claude Code'a giriş yap.",
            .profileAlreadyAdded: "Bu profil zaten ekli.",
            .accountName: "Hesap adı",
            .accountNameHelp: "Menüde görünecek kısa adı yaz.",
            .add: "Ekle",
            .cancel: "İptal",
            .accountNameEmpty: "Hesap adı boş olamaz.",
            .defaultAccountLabel: "Claude hesabı",
            .usageUsed: "%@: %@ kullanıldı",
            .extraUsageWithLimit: "Ek kullanım: $%.2f / $%.2f",
            .extraUsage: "Ek kullanım: $%.2f",
            .resetDaysHours: "%dg %dsa sonra sıfırlanır",
            .resetHours: "%dsa sonra sıfırlanır",
            .resetMinutes: "%ddk sonra sıfırlanır",
            .keychainReadFailed: "Keychain kaydı okunamadı (%d). Bu profil Claude Code ile giriş yapmış mı?",
            .malformedCredential: "Claude Code kimlik kaydı beklenen biçimde değil.",
            .missingRefreshToken: "Refresh token yok; bu profil için bir kez claude auth login çalıştır.",
            .missingScopes: "OAuth scope bilgisi yok; bu profil için bir kez claude auth login çalıştır.",
            .cliNotFound: "Claude Code bulunamadı. Claude Code'u kurup ClaudeHub'ı yeniden aç.",
            .loginRefreshFailed: "Claude Code oturumu yenileyemedi; bu profil için bir kez claude auth login çalıştır.",
            .invalidAnthropicResponse: "Anthropic geçersiz bir yanıt döndürdü.",
            .anthropicHTTPFailed: "Anthropic isteği HTTP %d ile başarısız oldu.",
        ],
        .en: [
            .confirmRemoveAccount: "Remove %@?",
            .removeAccountHelp: "The account will be removed from ClaudeHub. Its Claude Code profile folder and session will not be deleted.",
            .sessionExpired: "Session expired. Run claude auth login with this profile’s CLAUDE_CONFIG_DIR, then reconnect.",
            .refreshTokenExpiring: "Session renewal expires soon or has expired. Sign in again for this profile.",
            .accountStoreUnavailable: "The account file could not be read or saved. The existing file was preserved; a .bak backup was attempted for invalid JSON. Check accounts.json and restart the app. Account changes are disabled.",
            .noAccounts: "No accounts added yet",
            .refreshNow: "Refresh Now",
            .accounts: "Accounts",
            .quit: "Quit ClaudeHub",
            .loading: "Loading…",
            .error: "Error: %@",
            .fiveHour: "5 hours",
            .sevenDay: "7 days",
            .sevenDaySonnet: "7-day Sonnet",
            .sevenDayOpus: "7-day Opus",
            .oauthApps: "OAuth applications",
            .cowork: "Cowork",
            .updated: "Updated: %@",
            .addProfile: "Add Existing Claude Profile…",
            .removeAccount: "Remove Account",
            .pickerTitle: "Select Claude Code Profile Folder",
            .select: "Select",
            .missingClaudeJSON: "This folder does not contain .claude.json. Sign in to Claude Code with this CLAUDE_CONFIG_DIR first.",
            .profileAlreadyAdded: "This profile is already added.",
            .accountName: "Account Name",
            .accountNameHelp: "Enter a short name to display in the menu.",
            .add: "Add",
            .cancel: "Cancel",
            .accountNameEmpty: "Account name cannot be empty.",
            .defaultAccountLabel: "Claude account",
            .usageUsed: "%@: %@ used",
            .extraUsageWithLimit: "Extra usage: $%.2f / $%.2f",
            .extraUsage: "Extra usage: $%.2f",
            .resetDaysHours: "resets in %dd %dh",
            .resetHours: "resets in %dh",
            .resetMinutes: "resets in %dmin",
            .keychainReadFailed: "Could not read the Keychain item (%d). Is this profile signed in to Claude Code?",
            .malformedCredential: "The Claude Code credential has an unexpected format.",
            .missingRefreshToken: "No refresh token. Run claude auth login once for this profile.",
            .missingScopes: "No OAuth scope information. Run claude auth login once for this profile.",
            .cliNotFound: "Claude Code was not found. Install Claude Code and reopen ClaudeHub.",
            .loginRefreshFailed: "Claude Code could not renew the session. Run claude auth login once for this profile.",
            .invalidAnthropicResponse: "Anthropic returned an invalid response.",
            .anthropicHTTPFailed: "The Anthropic request failed with HTTP %d.",
        ],
        .fr: [
            .confirmRemoveAccount: "Supprimer %@ ?",
            .removeAccountHelp: "Le compte sera retiré de ClaudeHub. Son dossier de profil et sa session Claude Code ne seront pas supprimés.",
            .sessionExpired: "Session expirée. Exécutez claude auth login avec le CLAUDE_CONFIG_DIR de ce profil, puis reconnectez-le.",
            .refreshTokenExpiring: "Le renouvellement de session expire bientôt ou a expiré. Reconnectez-vous à ce profil.",
            .accountStoreUnavailable: "Impossible de lire ou enregistrer les comptes. Le fichier existant est conservé ; une sauvegarde .bak a été tentée pour le JSON invalide. Vérifiez accounts.json et relancez l’application. Les modifications sont désactivées.",
            .noAccounts: "Aucun compte ajouté",
            .refreshNow: "Actualiser maintenant",
            .accounts: "Comptes",
            .quit: "Quitter ClaudeHub",
            .loading: "Chargement…",
            .error: "Erreur : %@",
            .fiveHour: "5 heures",
            .sevenDay: "7 jours",
            .sevenDaySonnet: "Sonnet sur 7 jours",
            .sevenDayOpus: "Opus sur 7 jours",
            .oauthApps: "Applications OAuth",
            .cowork: "Cowork",
            .updated: "Mis à jour : %@",
            .addProfile: "Ajouter un profil Claude existant…",
            .removeAccount: "Supprimer un compte",
            .pickerTitle: "Sélectionner le dossier du profil Claude Code",
            .select: "Sélectionner",
            .missingClaudeJSON: "Ce dossier ne contient pas de fichier .claude.json. Connectez-vous d'abord à Claude Code avec ce CLAUDE_CONFIG_DIR.",
            .profileAlreadyAdded: "Ce profil est déjà ajouté.",
            .accountName: "Nom du compte",
            .accountNameHelp: "Saisissez un nom court à afficher dans le menu.",
            .add: "Ajouter",
            .cancel: "Annuler",
            .accountNameEmpty: "Le nom du compte ne peut pas être vide.",
            .defaultAccountLabel: "Compte Claude",
            .usageUsed: "%@ : %@ utilisés",
            .extraUsageWithLimit: "Utilisation supplémentaire : $%.2f / $%.2f",
            .extraUsage: "Utilisation supplémentaire : $%.2f",
            .resetDaysHours: "réinitialisation dans %dj %dh",
            .resetHours: "réinitialisation dans %dh",
            .resetMinutes: "réinitialisation dans %d min",
            .keychainReadFailed: "Impossible de lire l'élément du trousseau (%d). Ce profil est-il connecté à Claude Code ?",
            .malformedCredential: "L'identifiant Claude Code présente un format inattendu.",
            .missingRefreshToken: "Aucun refresh token. Exécutez claude auth login une fois pour ce profil.",
            .missingScopes: "Aucune information de scope OAuth. Exécutez claude auth login une fois pour ce profil.",
            .cliNotFound: "Claude Code est introuvable. Installez Claude Code puis relancez ClaudeHub.",
            .loginRefreshFailed: "Claude Code n'a pas pu renouveler la session. Exécutez claude auth login une fois pour ce profil.",
            .invalidAnthropicResponse: "Anthropic a renvoyé une réponse non valide.",
            .anthropicHTTPFailed: "La requête Anthropic a échoué avec le code HTTP %d.",
        ],
        .es: [
            .confirmRemoveAccount: "¿Eliminar %@?",
            .removeAccountHelp: "La cuenta se eliminará de ClaudeHub. No se borrarán su carpeta de perfil ni su sesión de Claude Code.",
            .sessionExpired: "La sesión ha caducado. Ejecuta claude auth login con el CLAUDE_CONFIG_DIR de este perfil y vuelve a conectarlo.",
            .refreshTokenExpiring: "La renovación de sesión caduca pronto o ya caducó. Inicia sesión de nuevo en este perfil.",
            .accountStoreUnavailable: "No se pudo leer o guardar el archivo de cuentas. Se conservó el archivo existente y se intentó crear una copia .bak del JSON inválido. Revisa accounts.json y reinicia la app. Los cambios están desactivados.",
            .noAccounts: "Aún no se han añadido cuentas",
            .refreshNow: "Actualizar ahora",
            .accounts: "Cuentas",
            .quit: "Salir de ClaudeHub",
            .loading: "Cargando…",
            .error: "Error: %@",
            .fiveHour: "5 horas",
            .sevenDay: "7 días",
            .sevenDaySonnet: "Sonnet de 7 días",
            .sevenDayOpus: "Opus de 7 días",
            .oauthApps: "Aplicaciones OAuth",
            .cowork: "Cowork",
            .updated: "Actualizado: %@",
            .addProfile: "Añadir un perfil de Claude existente…",
            .removeAccount: "Eliminar cuenta",
            .pickerTitle: "Seleccionar carpeta del perfil de Claude Code",
            .select: "Seleccionar",
            .missingClaudeJSON: "Esta carpeta no contiene .claude.json. Inicia sesión en Claude Code con este CLAUDE_CONFIG_DIR primero.",
            .profileAlreadyAdded: "Este perfil ya está añadido.",
            .accountName: "Nombre de la cuenta",
            .accountNameHelp: "Escribe un nombre corto para mostrarlo en el menú.",
            .add: "Añadir",
            .cancel: "Cancelar",
            .accountNameEmpty: "El nombre de la cuenta no puede estar vacío.",
            .defaultAccountLabel: "Cuenta de Claude",
            .usageUsed: "%@: %@ usado",
            .extraUsageWithLimit: "Uso adicional: $%.2f / $%.2f",
            .extraUsage: "Uso adicional: $%.2f",
            .resetDaysHours: "se restablece en %dd %dh",
            .resetHours: "se restablece en %dh",
            .resetMinutes: "se restablece en %d min",
            .keychainReadFailed: "No se pudo leer el elemento del llavero (%d). ¿Este perfil ha iniciado sesión en Claude Code?",
            .malformedCredential: "La credencial de Claude Code tiene un formato inesperado.",
            .missingRefreshToken: "No hay refresh token. Ejecuta claude auth login una vez para este perfil.",
            .missingScopes: "No hay información de scopes OAuth. Ejecuta claude auth login una vez para este perfil.",
            .cliNotFound: "No se encontró Claude Code. Instala Claude Code y vuelve a abrir ClaudeHub.",
            .loginRefreshFailed: "Claude Code no pudo renovar la sesión. Ejecuta claude auth login una vez para este perfil.",
            .invalidAnthropicResponse: "Anthropic devolvió una respuesta no válida.",
            .anthropicHTTPFailed: "La solicitud a Anthropic falló con HTTP %d.",
        ],
    ]
}
