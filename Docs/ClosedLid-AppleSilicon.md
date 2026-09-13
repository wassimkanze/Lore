# Maintenir les agents actifs, clapet fermé — Apple Silicon

Étude du 10 septembre 2026, mise à jour d’implémentation du 12 septembre 2026. Cible : Mac à puce Apple Silicon uniquement, macOS 15+. Environnement de développement observé : arm64, macOS 26.6.2. Aucun réglage global de veille ni aucune règle sudoers n’ont été modifiés. Après l’étude, le service privilégié a été enregistré le 12 septembre avec l’accord explicite de l’utilisateur.

## Conclusion

Le comportement demandé est techniquement plausible et déjà proposé par des utilitaires sur Apple Silicon : les calculs continuent, l'écran intégré reste éteint une fois le clapet fermé, puis macOS gère son rallumage à la réouverture. Ce n'est pas ce que garantit une simple assertion anti-veille par inactivité. Nous avons identifié un mécanisme concret et des précédents, mais **pas encore effectué un test physique de ce mode sur ce Mac**. Ni la continuité d'un agent, ni l'état réel de l'écran ne peuvent être certifiés à partir d'un booléen logiciel.

La précédente réserve doit donc être reformulée : ce n'est pas « impossible sur Mac M », c'est « possible avec une intégration système supplémentaire et une validation matérielle ». L'affirmation « tous les Mac M, toutes les versions, sur batterie et sans écran externe » serait prématurée.

## Les preuves et leurs limites

1. **Amphetamine reconnaît explicitement Apple Silicon.** Son projet Power Protect explique que les transitions entre secteur et batterie peuvent perturber le mode écran fermé et décrit un composant nécessitant une authentification administrateur. Cela prouve l'existence d'un mode ciblant cette plateforme, mais ne valide pas Lore ni chaque version actuelle de macOS. [Source du développeur](https://github.com/x74353/Amphetamine-Power-Protect)

2. **Le réglage `disablesleep` existe dans le code Apple.** Le parseur de `pmset` le classe parmi les réglages globaux, indépendants de la source d'alimentation, et destinés à être enregistrés. L'option n'est pas décrite dans la page de manuel locale consultée ; il ne faut donc pas la présenter comme une API publique stable de gestion du clapet. Aucun appel modifiant cette option n'a été exécuté. [Source Apple de pmset](https://github.com/apple-oss-distributions/PowerManagement/blob/main/pmset/pmset.m)

3. **L'effet est plus large que le clapet.** Dans le code public du noyau Apple, `userDisabledAllSleep` est vérifié au début de `checkSystemSleepAllowed`, avant d'autres conditions. C'est une désactivation globale de la veille, pas une simple permission de travailler écran fermé. Ce code public n'est pas une attestation de tous les détails de la version livrée sur ce Mac, mais suffit à justifier une restauration indépendante et des essais prudents. [Source Apple du noyau](https://github.com/apple-oss-distributions/xnu/blob/main/iokit/Kernel/IOPMrootDomain.cpp)

4. **Un précédent natif utilise un service privilégié.** Le projet Amped décrit un LaunchDaemon enregistré avec SMAppService, un canal XPC vérifiant l'équipe de signature et des opérations limitées au réglage de veille. C'est un précédent d'architecture, pas une dépendance intégrée ni du code recopié dans Lore. [Source du développeur](https://github.com/gustaferiksson/amped), [SMAppService — Apple](https://developer.apple.com/documentation/servicemanagement/smappservice)

5. **La voie publique standard reste distincte.** Apple indique qu'une assertion `PreventUserIdleSystemSleep` laisse l'écran se reposer et n'empêche pas nécessairement la veille due au clapet. C'est le mode standard implémenté aujourd'hui dans le contrôle de pulsation de Lore, avec une échéance gérée par macOS et libération à la sortie du processus. [Documentation Apple](https://developer.apple.com/documentation/iokit/kiopmassertiontypepreventuseridlesystemsleep)

## Comportement produit à viser

Un mode séparé « Continuer clapet fermé » et un indicateur de statut explicite. Il serait désactivé au lancement et ne serait jamais confondu avec le mode standard.

- Fermeture : aucune assertion empêchant l'extinction de l'écran. Les calculs doivent réellement continuer.
- Réouverture : macOS réveille l'écran normalement ; le verrouillage de session reste respecté. Ne pas modifier la luminosité, désactiver le verrouillage, falsifier le capteur du clapet ou synthétiser une activité utilisateur continue.
- Phase initiale : session courte, Mac sur secteur et surface ventilée. Le fonctionnement sur batterie viendrait après validation dédiée, avec un seuil d'arrêt conservateur.
- Fin des tâches, expiration, perte du lien avec Lore, arrêt du service ou redémarrage : restauration contrôlée de l'état antérieur.
- L'interface distingue « demandé », « réglage confirmé » et « essai matériel réussi ». Un retour de commande réussi n'est pas présenté comme une preuve que le CPU, le réseau et l'agent ont continué.

L'écran éteint ne veut pas dire machine endormie. Le mode vise précisément à séparer les deux, sans empêcher l'écran de s'éteindre ni forcer son déverrouillage.

## Implémentation et autorisation validées — essai physique restant

L’app et son petit service privilégié sont maintenant signés avec une identité Apple Development stable. Le binaire Release est installé dans `~/Applications/Lore.app`. Le service embarqué a été enregistré avec l’accord explicite de l’utilisateur. macOS affiche l’activité de Lore autorisée ; launchd exécute le service et l’appel XPC de statut aboutit. **Aucun changement de `disablesleep` n’a été effectué** : la session clapet fermé reste éteinte.

Parcours dans **Settings → Closed-lid mode** :

1. « Set up power authorization… » enregistre le service via `SMAppService` ; macOS demande l’approbation administrateur, éventuellement dans Login Items & Extensions.
2. Une fois l’autorisation effective, les durées de 15 minutes, 1 heure, 2 heures ou 4 heures demande une session distincte du mode standard.
3. « Stop » rend immédiatement la veille normale ; « Remove power authorization » désenregistre le service lorsqu’aucune session ou restauration n’est en cours.

Le service utilise seulement des commandes fixes `pmset`, sans shell, commande ou chemin arbitraire reçu du client. L’identité XPC est vérifiée dans les deux sens : équipe, identifiant de signature exact et absence de l’entitlement de débogage `get-task-allow`. Les builds Debug ne peuvent pas activer cette intégration.

Le moteur de session :

- exige Apple Silicon, un MacBook sur batterie ou secteur, une batterie supérieure à 20 % et un état thermique nominal ou fair ; une mesure absente refuse ou interrompt la session ;
- refuse de prendre possession d’une désactivation de veille déjà active ;
- écrit un journal de restauration avant mutation dans `/Library/Application Support/LorePowerHelper`, répertoire root en mode 0700 ;
- possède une échéance fixe maximale de quatre heures et exige un heartbeat toutes les 10 secondes ; après 30 secondes sans heartbeat, la restauration est déclenchée au prochain contrôle (toutes les 5 secondes) ;
- restaure aussi lors d’une déconnexion XPC, d’un arrêt demandé, d’une batterie atteignant 20 %, de mesures d’alimentation indisponibles ou d’une pression thermique excessive ;
- relit le réglage après transition et conserve le journal si la restauration échoue, afin de réessayer ;
- restaure avant d’accepter une nouvelle session après un redémarrage du service ; aucune activation automatique au lancement de Lore.

Les appels `pmset` sont bornés à trois secondes pour ne pas bloquer indéfiniment le contrôle de récupération. Le journal est validé (propriétaire root, fichier régulier, taille bornée, pas de lien symbolique). Le contrôle standard continue d’utiliser une assertion IOPM indépendante.

**Limites :** `disablesleep` est un réglage global non documenté comme API publique stable du clapet. Une coordination exclusive parfaite avec un autre utilitaire n’est pas possible. Un crash du service nécessite son redémarrage par launchd pour restaurer ; une indisponibilité persistante du système ne peut pas être corrigée par une promesse de l’interface. L’autorisation SMAppService et l’appel XPC de statut sont validés sur ce Mac. Le cycle de mise à jour du binaire privilégié et la continuité physique clapet fermé restent à valider.

## Validation physique requise

Sur au moins un MacBook Apple Silicon, puis d'autres générations prises en charge :

1. Lire l'état initial ; faire un essai court, sur secteur, sans écran externe.
2. Faire tourner un processus témoin local qui écrit uniquement un compteur/horodatage dans un dossier de test Lore.
3. Fermer le clapet 60 à 120 secondes, puis le rouvrir ; vérifier la continuité des mesures avec une horloge monotone, l'absence d'événement de veille et le fonctionnement réel de l'agent.
4. Vérifier séparément que la dalle s'éteint à la fermeture et se rallume à la réouverture, avec le verrouillage habituel.
5. Répéter avec chargeur débranché/rebranché, batterie au seuil choisi, fin de session, arrêt forcé de Lore et redémarrage du service.
6. Vérifier que le retour à la veille fonctionne après chaque essai et après redémarrage. Ne pas provoquer une surchauffe ou une batterie critique pour tester : injecter ces conditions dans les tests du service.

Cette phase nécessite un opérateur pour fermer et rouvrir physiquement le Mac. Elle n'a pas été remplacée par une simulation ou une affirmation de fonctionnement.

## Vérifications réellement effectuées

- Binaire Lore inspecté avec `lipo` : arm64 uniquement.
- Tests automatisés du moteur : propriété de session, échéance fixe, heartbeat, refus de reprise d’un réglage existant, secteur/température, mesures absentes, journal de récupération, échec de restauration et nouvelle tentative. Les tests injectent le backend ; ils ne modifient jamais la veille réelle.
- Signature Release de l’app et du service vérifiée ; le contrôle non privilégié `LorePowerHelper --validate-signature` valide son identité et la syntaxe de la règle de signature.
- Assertion standard créée via le bouton « 30 minutes », observée dans `pmset -g assertions` sous le processus Lore, puis libérée via « Stop ».
- Diagnostic reproductible : `swift run LoreDiagnostics --check-power` crée et libère immédiatement une assertion standard temporisée. Il n'active pas le mode clapet fermé.
- Aucun essai physique clapet fermé et aucune bascule du réglage global `disablesleep`.


## Essai instrumenté disponible depuis le 13 septembre

Settings → Validate on this Mac lance un test de trois minutes, distinct des sessions normales de plusieurs heures. Il peut fonctionner sans chargeur ; la batterie doit rester supérieure à 20 % et l’état thermique admissible. Le test échantillonne `AppleClamshellState` via le service IOKit `IOPMrootDomain` et utilise une horloge continue pour détecter une interruption d’exécution. Il demande de fermer le clapet 30 à 60 secondes, puis de le rouvrir, et libère ensuite sa session de veille. Le rapport JSON local inclut la source d’alimentation initiale, la durée observée clapet fermé, le plus grand intervalle entre mesures et le résultat de restauration. Il ne prétend pas certifier l’écran ou la réponse de chaque agent.

Un Mac actif dans un sac fermé manque de ventilation : ce mode n’est pas une garantie de transport sûr. Le fonctionnement prolongé vise une surface ventilée ; laisser dormir le Mac pour le transporter dans un sac.


## Résultat réel — 13 septembre 2026

Le premier essai instrumenté **sur batterie, sans chargeur**, a réussi : 52,40 secondes clapet fermé, plus grand intervalle entre mesures 1,095 seconde, aucun échantillon de capteur manquant. Une commande locale Codex a aussi été exécutée alors que le capteur indiquait le clapet fermé. À la réouverture, Lore a arrêté sa session et `pmset -g` a confirmé `SleepDisabled = 0`. Le rapport `last-lid-test.json` indique `startedOnACPower: false`, `samplingConfirmed: true` et `sleepRestored: true`.

Un second contrôle a activé une session puis quitté normalement Lore : le service est resté disponible et a restauré `SleepDisabled = 0` à la disparition de son client. Les seuils batterie/température, échéances et erreurs de récupération sont couverts par des tests avec backend injecté ; nous n’avons pas provoqué physiquement de batterie critique ni de surchauffe. Les sessions de plusieurs heures et les autres modèles de Mac n’ont pas encore de validation matérielle prolongée.

L’utilisateur n’a pas perçu d’interruption de sa tâche et n’a pas dû ressaisir son mot de passe à la réouverture. Il ne peut pas confirmer visuellement l’état de la dalle lorsqu’elle est fermée : l’extinction de l’écran reste donc non vérifiée. Aucun réglage de verrouillage ou d’authentification n’a été modifié par Lore.
