1. Création des rôles hiérarchiques

Vous créez quatre rôles principaux, chacun représentant un niveau d’accès bien défini dans votre système CHCL :

a) chcl_admin — Administrateur système

Peut se connecter (LOGIN)

Pas SUPERUSER mais possède tous les privilèges grâce aux GRANTs

Expire le 31 décembre 2026

Limite de connexion : 10

C’est le rôle le plus puissant (accès total et sans RLS)

b) gestionnaire — Chef de département / responsable pédagogique

Peut se connecter

Connexion limitée à 20

Accès intermédiaire : lecture/écriture de toutes les tables pédagogiques

Restreint par RLS aux données de son programme

c) professeur_role — Professeur

Peut se connecter

Connexion limitée à 50

Accès partiel : lecture de ses propres données + modification de ses créneaux

RLS appliqué pour n’autoriser que ses propres données

d) consultation — Étudiants et personnel administratif

Accès en lecture seule

RLS impose qu’ils ne voient que les données actives (professeurs actifs, créneaux confirmés

3. Attribution des privilèges (GRANT)

Les privilèges sont structurés par rôle.

a) chcl_admin — privilèges complets

Accès total sur :

le schéma

toutes les tables

toutes les séquences

toutes les fonctions

toutes les procédures

C’est un administrateur complet du schéma gestion_emploi_temps.

b) gestionnaire — accès étendu mais contrôlé

Accès lecture + écriture sur :

professeurs

matieres

creneaux_horaires

affectations_professeurs

salles

batiments

programmes

Accès USAGE sur les séquences.

Mais RLS limitera son accès aux professeurs de son programme.

c) professeur_role — accès limité

Lecture sur un ensemble large de tables (professeurs, matières, salles, etc.)

Permissions d'écriture uniquement sur les créneaux

Peut exécuter certaines fonctions métier (verifier_disponibilite)

RLS limite toutes ces opérations à ses propres données.

d) consultation — lecture seule

Ils peuvent consulter :

vues publiques (emplois du temps, calendrier académique…)

quelques tables de référence (salles, programmes…)

Et RLS filtre encore davantage (professeurs actifs seulement, etc.)

4. Activation du RLS sur les tables sensibles

Les tables suivantes sont sécurisées :

professeurs

creneaux_horaires

affectations_professeurs

matieres

Cela signifie :

Même si un rôle a GRANT SELECT sur la table,
il ne verra que les lignes autorisées par les politiques RLS.


