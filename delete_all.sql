-- =============================================
-- SCRIPT DE NETTOYAGE COMPLET (A executer avant de relancer le script DDL)
-- =============================================

-- 1. REVOCATION ET SUPPRESSION DES UTILISATEURS DE TEST (Roles LOGIN)
-- Important : Le nom d'utilisateur avec @ doit etre entre guillemets doubles.

DROP USER IF EXISTS "pierre_michel.augustin@ueh.edu.ht";
DROP USER IF EXISTS "gestionnaire_informatique@ueh.edu.ht";
DROP USER IF EXISTS consult_user;
DROP USER IF EXISTS chcl_admin_user;

-- 2. SUPPRESSION DES ROLES (Groupes)
-- Assurez-vous qu'aucun autre utilisateur n'est membre de ces roles avant de les supprimer
DROP ROLE IF EXISTS consultation;
DROP ROLE IF EXISTS professeur_role;
DROP ROLE IF EXISTS gestionnaire;
DROP ROLE IF EXISTS chcl_admin;


-- 3. SUPPRESSION DU SCHEMA PRINCIPAL ET DE TOUT CE QU'IL CONTIENT
-- CASCADE supprime toutes les tables, vues, fonctions et sequences qui se trouvent a l'interieur.
DROP SCHEMA IF EXISTS gestion_emploi_temps CASCADE;

-- 4. SUPPRESSION DE L'EXTENSION
DROP EXTENSION IF EXISTS btree_gist;

-- Suppression des fonctions/vues/triggers qui pourraient avoir ete creees
-- Si vous avez des doutes sur l'emplacement des fonctions/vues, la suppression du schema le gere.
-- Si des fonctions etaient creees hors du schema, il faudrait les supprimer explicitement (mais ici, elles sont dans le schema).

-- Fin du script de nettoyage