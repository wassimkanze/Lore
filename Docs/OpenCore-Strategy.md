# Lore — proposition open core

Document de travail, pas une décision de licence ni une grille commerciale définitive. Aucune restriction, activation ou facturation n’est implémentée. Aucun dépôt n’est publié par cette étape.

## Ce que l’on vend

Lore reste une mémoire locale du développement. La proposition gratuite permet de comprendre son activité ; le Pro aide à retrouver et raconter ce qui a été construit. Pulse et les compteurs de tokens apportent une utilité quotidienne, mais ne devraient pas devenir le centre de la proposition payante.

| Gratuit / cœur public proposé | Pro / module privé proposé |
| --- | --- |
| Collecteurs Codex, Claude Code et Gemini CLI, Git en lecture seule | Résumés locaux de journées, semaines et projets, reliés à leurs preuves |
| Calendrier et historique brut conservé sans limite artificielle | Recherche en langage naturel dans l’historique (« quand ai-je construit… ») |
| Projets, sessions, commits, liens directs vers les chats | Rapprochement d’une fonctionnalité entre sessions, branches et projets |
| Pulse, notch, accès locaux et contrôles de sécurité | Mémoire des décisions techniques avec références vérifiables |
| Recherche textuelle et métriques descriptives | Bilans de livraison et comptes rendus clients personnalisables |
| Export de base des données, à implémenter | Rapports mis en forme et exports de synthèses |

La colonne Pro est une proposition de feuille de route, pas une liste de fonctionnalités disponibles. Avant de la vendre, prototyper la qualité réelle des résumés et de la recherche. Une synthèse doit renvoyer à des sessions/commits et permettre la correction, plutôt que produire un récit invérifiable. Aucun score de productivité.

Je déconseille de rendre payantes après publication des fonctions déjà offertes, de restreindre artificiellement l’historique brut, ou de facturer la protection de la vie privée. Les intégrations de base ouvertes peuvent aussi faciliter les contributions de la communauté.

## Séparation du code à viser

- Dépôt public : application Community compilable seule, modèles, stockage, collecteurs, contrôles d’accès, Git, Pulse et service système auditable, tests et documentation.
- Dépôt privé : moteur Pro, vues de synthèse/recherche et distribution commerciale. Le module utilise des interfaces publiques explicites ; le cœur public ne dépend jamais d’un dépôt privé pour compiler.
- Une composition commerciale inclut les deux. Éviter d’éparpiller `if isPro` dans les parseurs et le stockage, ou de publier une implémentation propriétaire en espérant qu’un contrôle de licence masque son fonctionnement.
- Garder les données brutes portables et utilisables sans Pro. Les index dérivés et synthèses peuvent rester des données distinctes, reconstruisibles.

Ne pas créer maintenant un framework de plugins ou un système de droits fictif. La première vraie fonctionnalité Pro déterminera l’interface minimale à extraire.

## Licence : choisir consciemment

Une licence réellement open source autorise la redistribution et les usages commerciaux. Elle ne peut pas interdire aux entreprises d’utiliser ou de revendre le cœur. Une clause « usage non commercial uniquement » ne correspondrait donc pas à la définition open source de l’OSI. [Définition OSI](https://opensource.org/osd)

**MPL-2.0 est un candidat à examiner** : son copyleft porte sur les fichiers couverts et permet de les combiner avec des fichiers propriétaires. Lors d’une distribution, les modifications des fichiers couverts restent soumises aux obligations de mise à disposition du code. Cela correspond assez bien à un cœur public amélioré collectivement et un module Pro distinct. [FAQ officielle Mozilla, notamment Q1 et Q8–Q11](https://www.mozilla.org/en-US/MPL/2.0/FAQ/)

**MIT est une alternative plus permissive** : simple pour les réutilisateurs, elle permet notamment la modification, la redistribution et la vente en conservant les notices requises. Elle n’impose pas de publier les améliorations d’un fork. [Texte MIT](https://opensource.org/license/mit)

Le choix final doit précéder la publication et tenir compte des contributions, dépendances et licences des éventuels modèles IA. Gérer séparément les droits sur le nom et le logo. Un fork ne devient pas automatiquement une distribution officielle de Lore.

## Modèle économique à tester

Pour un produit qui fonctionne localement, une licence perpétuelle pour une version, avec une période de mises à jour incluse puis renouvellement facultatif, me paraît cohérente. Le client garde la version achetée ; un abonnement serait plus facile à justifier pour un service récurrent réel que pour déverrouiller des données locales.

Ne pas fixer de prix avant de démontrer la valeur d’au moins une fonction Pro. Une licence signée vérifiable hors ligne est une piste pour éviter de dépendre d’un serveur à chaque lancement. Le paiement et la distribution peuvent nécessiter un service commercial sans que les données de développement lui soient transmises. Les modèles locaux ont leurs propres exigences matérielles et droits de redistribution à vérifier.

## Avant toute publication

Vérifier les exclusions des bases locales, caches, sauvegardes et journaux de test ; retirer les chemins personnels et paramètres locaux de signature des artefacts publiés. Définir la licence, les règles de contribution et le périmètre de la marque. Ne pas transformer le dépôt actuel en dépôt public sans cette revue explicite.
