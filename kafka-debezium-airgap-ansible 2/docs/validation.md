# Validation de la variante v1.1.0 sans PKI

Contrôles locaux réalisés le 9 septembre 2026, avec ansible-core 2.16.14, Jinja 3.1.6 et Python 3.12.14. Ces versions décrivent l'environnement de test, pas une validation du Python ou de systemd des VM cibles.

| Contrôle | Résultat et portée |
|---|---|
| Syntaxe Ansible | `site.yml`, `verify.yml` et les quatre playbooks de test : valides |
| YAML et scripts shell | YAML analysé, yamllint avec règles de style adaptées au projet, syntaxe Bash des scripts et du rendu ACL : valides |
| Rendu des modèles | 27 fichiers rendus localement avec l'inventaire d'exemple et des mots de passe factices distincts |
| Configuration SASL | Identités/cohérence des secrets, listeners broker/contrôleur, clients Connect avec préfixes producer/consumer/admin, AKHQ, exporter, CLI et historique Oracle : vérifiés dans les rendus |
| Absence de PKI | Aucun keystore/truststore ou chemin PKI dans les rendus ; rôle et test PKI anciens retirés |
| Secrets persistants | Deux passages du rôle credentials : secrets inchangés, fichiers Kafka en mode 0600, absence de génération PKI |
| Ouvertures admin | Deux passages sur un simulateur firewalld strict : zones permanentes/courantes, absence de source CIDR, pas d'ajout répété ; scénarios toolbox et Connect |
| Garde de migration | États simulés : installation neuve acceptée, TLS actif refusé, cluster arrêté accepté |

Les tests firewalld et migration sont des simulations locales. Ils ne démontrent pas l'accessibilité depuis tous les réseaux réels et ne valident pas les interactions avec une politique firewalld/SELinux d'entreprise.

Non effectués ici : installation sur RHEL 8.10, démarrage réel du quorum Kafka/Connect et des services toolbox, connexion à PostgreSQL/Oracle, test de charge, migration d'une stack existante, authentification réelle des interfaces et vérification de leurs versions binaires. Le bundle binaire n'est pas inclus dans l'archive et doit toujours être fourni avant déploiement.

La recette distante reste à exécuter avec `ansible-playbook verify.yml`, complétée par l'accès aux interfaces depuis chaque réseau attendu et un test CDC représentatif. Le code inchangé des autres composants ne constitue pas une nouvelle certification de compatibilité de leurs versions.
