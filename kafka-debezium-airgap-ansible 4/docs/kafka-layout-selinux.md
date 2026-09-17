# Kafka sous /inte : chemins, droits et SELinux

## Implantation et propriétaires

| Usage | Chemin | Propriétaire prévu |
|---|---|---|
| Distribution Kafka | `/inte/vq/DAT/infr/KFK/kafka` | root:root |
| Configuration | `/inte/vq/DAT/data/KFK/kraft` | root:ivqdkfk1, répertoire 0750, secrets 0640 |
| Journaux de données Kafka | `/inte/vq/DAT/data/KFK/kafka` | ivqdikfk:ivqdkfk1 |
| Métadonnées KRaft | `/inte/vq/DAT/data/KFK/kraft-metadata` | ivqdikfk:ivqdkfk1 |
| Logs applicatifs | `/var/log/kafka` | ivqdikfk:ivqdkfk1 |

Le service reste `kafka.service`. Son `User`, son `Group`, ses commandes de démarrage/arrêt, ses chemins en lecture/écriture, les limites nofile, les commandes ACL et les contrôles de quorum utilisent les variables d'inventaire.

Le rôle recherche les comptes avec `getent`. Un compte existant (local ou NSS/SSSD) conserve ses attributs. Les comptes absents sont créés localement sans UID/GID imposé ; précréez-les si votre organisation impose des identifiants numériques. Systemd et le formatage Kafka utilisent explicitement le groupe demandé, même si le groupe principal du compte existant est différent.

Les permissions Unix des parents existants ne sont pas élargies automatiquement. Le rôle vérifie les accès sous l'identité de service : exécution des scripts, lecture de la configuration et écriture des données/métadonnées/logs. En cas d'échec, inspectez `namei -l <chemin>` et les ACL Unix des parents.

## Montages

Montez les volumes et configurez leur persistance (fstab/unités mount) avant le déploiement. `RequiresMountsFor=` ajoute les dépendances systemd correspondant aux chemins, mais ne crée ni les volumes ni les entrées fstab. Le rôle refuse `noexec` pour le montage des binaires. Le code ne remonte pas automatiquement les volumes et ne modifie pas fstab.

Les chemins doivent être absolus, normalisés et séparés ; les racines Kafka ne doivent pas être imbriquées ou passer par un lien symbolique. Un montage réseau ou un montage avec `context=` impose d'autres contraintes de labellisation : il ne faut pas supposer qu'un `restorecon` y suffira. La cible prévue est un stockage local/bloc avec labels étendus, tel que XFS/ext4.

## Ce que le playbook applique à SELinux

Le rôle utilise les outils RHEL, sans collection Galaxy ni téléchargement Internet. Il installe depuis les dépôts internes :

- `policycoreutils` ;
- `policycoreutils-python-utils` pour `semanage` ;
- `libselinux-utils` pour les vérifications de contexte.

Depuis la v1.2.1, le rôle exécute `ensure-fcontexts.sh` avec `/bin/bash`. La gestion des associations utilise `semanage fcontext`, puis les tâches Ansible appliquent et vérifient les labels avec `restorecon` et `matchpathcon`. Aucun script Python personnalisé, appel Python explicite, module SELinux Ansible supplémentaire ou outil `jq` n'est utilisé pour ces règles. Le script utilise Bash 4.4 et les outils système de RHEL 8 (`realpath`, `sort`). SELinux n'est ni désactivé ni passé en permissive.

Le paquet `policycoreutils-python-utils` reste nécessaire : il fournit `semanage`, qui dépend lui-même du Python système sur RHEL 8. Ansible conserve aussi ses dépendances Python. Cette modification remplace le code personnalisé de gestion SELinux ; elle ne supprime pas Python des VM.

Au prochain passage du rôle, l'ancien fichier `ensure-fcontexts.py` est supprimé du répertoire de configuration et remplacé par `ensure-fcontexts.sh`. Les associations SELinux existantes sont réutilisées. Aucun artefact SELinux supplémentaire n'est à télécharger pour l'environnement hors-ligne ; les paquets proviennent toujours des dépôts RHEL internes.

| Périmètre | Type de fichier par défaut |
|---|---|
| Arborescence d'installation | `usr_t` |
| Sous-répertoire `bin` et scripts | `bin_t` |
| Configuration | `etc_t` |
| Données et métadonnées | `var_lib_t` |
| Logs applicatifs | `var_log_t` |

Les types sont configurables via les variables `kafka_selinux_*_type`. Ce sont des types génériques de fichiers, **pas un domaine de processus Kafka dédié**. Le rôle n'impose pas un `SELinuxContext=`, n'installe pas de module d'autorisation global et ne modifie pas les types des ports. Le domaine réel du processus et ses droits dépendent de la politique targeted et des modules déjà installés sur les VM. Une politique d'entreprise confinant Java/Kafka peut nécessiter des règles complémentaires fondées sur ses refus AVC.

Les associations de chemins sont persistantes via `semanage fcontext`, puis appliquées par `restorecon`. La règle des exécutables est réappliquée après les règles générales quand une association change, pour conserver sa priorité. Un second passage sans dérive ne réécrit pas les associations.

Les ancêtres sont vérifiés individuellement. Avec `kafka_selinux_fix_unlabeled_parents: true`, un ancêtre dont le contexte attendu est `default_t`, `file_t` ou `unlabeled_t` reçoit une association exacte vers `usr_t`. Les autres types de parents sont conservés. Les parents font l'objet d'un `restorecon` **sans récursion** ; seuls les cinq répertoires Kafka font l'objet d'un parcours récursif. Il n'y a jamais de règle `/inte(/.*)?` ou de relabellisation récursive de tout `/inte`.

Les contextes effectifs sont contrôlés avant le formatage/démarrage. Le parcours des données par `restorecon -R` peut prendre du temps sur un stockage volumineux. Si une équipe gère déjà ces labels, `kafka_manage_selinux: false` permet de lui laisser cette gestion ; SELinux enforcing reste requis, et cette option n'accorde aucun droit supplémentaire.

Cette approche suit la gestion des chemins non standard décrite par [Red Hat pour RHEL 8](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/using_selinux/configuring-selinux-for-applications-and-services-with-non-standard-configurations_using-selinux). Pour les refus restants, Red Hat recommande d'abord d'analyser les contextes et la configuration avant de générer un module avec audit2allow : [diagnostic SELinux RHEL 8](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/using_selinux/troubleshooting-problems-related-to-selinux_using-selinux).

## Installation neuve

1. Renseigner l'inventaire, monter les volumes et rendre les artefacts disponibles.
2. Vérifier la disponibilité des trois RPM SELinux dans le dépôt interne.
3. Exécuter `ansible-playbook site.yml`.
4. Contrôler le quorum et les accès avec `ansible-playbook verify.yml`, puis les labels et AVC ci-dessous.

Aucun transfert depuis les anciens chemins n'est nécessaire pour des VM neuves.

## Migration d'un broker déjà déployé

**Changer les variables ne déplace pas les données.** Les topics, segments, checkpoints et métadonnées doivent être conservés intégralement, ainsi que `.state/` sur le contrôleur. Ne recopiez jamais le répertoire de métadonnées d'un autre broker.

1. Sauvegarder l'ancien projet, les unités/configurations, l'inventaire et `.state/`. Conserver les mêmes noms de brokers et le même ordre de calcul des node IDs.
2. Planifier un arrêt des producteurs/consommateurs et des workers Connect, puis des trois brokers. Cette procédure choisit une interruption complète pour simplifier le changement simultané de chemins et de comptes.
3. Pour chaque broker, préparer les nouveaux volumes puis copier **à froid et intégralement** l'ancien répertoire data vers le nouveau data, et l'ancien metadata vers le nouveau metadata. Conserver les deux fichiers `meta.properties` et tous les autres fichiers. Ne pas exécuter `kafka-storage.sh format` à la main.
4. Reprendre l'inventaire, le bundle et le `.state` de ce même cluster dans la nouvelle version du projet. Reprendre uniquement les personnalisations utiles sans rétablir les anciens chemins. Si les anciens répertoires n'étaient pas les valeurs de la v1.1.0, renseigner `kafka_previous_data_dir` et `kafka_previous_metadata_dir`.
5. Relancer `ansible-playbook site.yml` sur l'inventaire complet. Le garde refuse un broker encore actif avec une ancienne unité, une migration sans métadonnées cibles ou un transfert ne contenant qu'un des deux `meta.properties`. Il ne peut pas prouver que tous les segments ont été copiés : cette vérification appartient à l'opération de transfert.
6. Le rôle adapte les propriétaires des arborescences data/metadata/logs quand il détecte le changement d'unité (sans chmod récursif), vérifie les cluster/node IDs des deux stockages, applique les labels, puis démarre les services. Les binaires et configurations sont installés aux nouveaux emplacements.
7. Vérifier quorum, topics, ISR, offsets Connect et capture réelle avant de reprendre les flux. Conserver l'ancien stockage et l'ancienne unité pour le retour arrière jusqu'à validation.

Le garde suppose l'unité systemd gérée par ce projet. Il ne détecte pas un processus Kafka lancé manuellement ni tous les arrangements de drop-ins/unités fournis par un tiers. Vérifiez leur absence avant une migration. Pour une mise à jour ordinaire après migration, une unité déjà conforme n'impose pas un nouvel arrêt complet.

## Diagnostic sur les VM

Commandes à exécuter sur un broker :

```bash
getenforce
systemctl status kafka
systemctl cat kafka
findmnt -T /inte/vq/DAT/infr/KFK/kafka
namei -l /inte/vq/DAT/data/KFK/kraft/server.properties
ls -Zd /inte/vq/DAT/infr/KFK/kafka/bin /inte/vq/DAT/data/KFK/kafka /inte/vq/DAT/data/KFK/kraft-metadata /inte/vq/DAT/data/KFK/kraft
matchpathcon -V /inte/vq/DAT/infr/KFK/kafka/bin/kafka-server-start.sh
ps -eo label,user,group,args | grep '[k]afka.Kafka'
sudo ausearch -m AVC,USER_AVC -ts recent
journalctl -u kafka -b
```

`ausearch` provient du paquet RHEL `audit` s'il n'est pas déjà installé. Un `Permission denied` peut aussi venir des droits Unix, d'une ACL, d'un volume en lecture seule ou de `noexec` ; ne pas générer aveuglément des règles SELinux.

Aucun déploiement ni test d'application de politique sur vos VM n'a été effectué lors de la création de cette archive.
