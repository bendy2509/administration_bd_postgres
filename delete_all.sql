-- =============================================
-- SCRIPT DE RESET COMPLET - PROJET CHCL
-- =============================================

-- Sécurité : arrêter si erreur
-- \set ON_ERROR_STOP on

-- 1. Supprimer les triggers
DO $$
    BEGIN
        IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trigger_update_creneaux_timestamp') THEN
            DROP TRIGGER trigger_update_creneaux_timestamp ON gestion_emploi_temps.creneaux_horaires;
        END IF;
    END$$;

-- 2. Supprimer les fonctions
DROP FUNCTION IF EXISTS update_updated_at_column() CASCADE;
DROP FUNCTION IF EXISTS verifier_disponibilite(INTEGER, INTEGER, INTEGER, TIME, TIME, DATE) CASCADE;
DROP FUNCTION IF EXISTS ajouter_indisponibilite(INTEGER, TIME, TIME, DATE, DATE, TEXT) CASCADE;
DROP FUNCTION IF EXISTS modifier_creneau_professeur(INTEGER, TEXT, VARCHAR) CASCADE;

-- 3. Supprimer les vues
DROP VIEW IF EXISTS v_mes_creneaux CASCADE;
DROP VIEW IF EXISTS v_statistiques_professeurs CASCADE;
DROP VIEW IF EXISTS v_disponibilite_salles CASCADE;
DROP VIEW IF EXISTS v_emploi_temps_professeurs CASCADE;

-- 4. Supprimer les tables (ordre dépendances)
DROP TABLE IF EXISTS gestion_emploi_temps.affectations_professeurs CASCADE;
DROP TABLE IF EXISTS gestion_emploi_temps.creneaux_horaires CASCADE;
DROP TABLE IF EXISTS gestion_emploi_temps.matieres CASCADE;
DROP TABLE IF EXISTS gestion_emploi_temps.professeurs CASCADE;
DROP TABLE IF EXISTS gestion_emploi_temps.salles CASCADE;
DROP TABLE IF EXISTS gestion_emploi_temps.batiments CASCADE;
DROP TABLE IF EXISTS gestion_emploi_temps.programmes CASCADE;

-- 5. Supprimer les séquences automatiquement créées avec les SERIAL
DO $$
    DECLARE r RECORD;
    BEGIN
        FOR r IN
            SELECT sequence_schema, sequence_name
            FROM information_schema.sequences
            WHERE sequence_schema = 'gestion_emploi_temps'
            LOOP
                EXECUTE format('DROP SEQUENCE IF EXISTS %I.%I CASCADE', r.sequence_schema, r.sequence_name);
            END LOOP;
    END$$;

-- 6. Supprimer les rôles créés
DO $$
    BEGIN
        IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'chcl_admin') THEN
            EXECUTE 'REVOKE ALL PRIVILEGES ON DATABASE gestion_emploi_temps FROM chcl_admin';
            DROP ROLE chcl_admin;
        END IF;
        IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'gestionnaire') THEN
            EXECUTE 'REVOKE ALL PRIVILEGES ON DATABASE gestion_emploi_temps FROM gestionnaire';
            DROP ROLE gestionnaire;
        END IF;
        IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'professeur_role') THEN
            EXECUTE 'REVOKE ALL PRIVILEGES ON DATABASE gestion_emploi_temps FROM professeur_role';
            DROP ROLE professeur_role;
        END IF;
        IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'consultation') THEN
            EXECUTE 'REVOKE ALL PRIVILEGES ON DATABASE gestion_emploi_temps FROM consultation';
            DROP ROLE consultation;
        END IF;
    END$$;


-- 7. Supprimer les utilisateurs créés
DO $$
    BEGIN
        IF EXISTS (SELECT 1 FROM pg_user WHERE usename = 'pierre_michel.augustin@ueh.edu.ht') THEN
            DROP USER "pierre_michel.augustin@ueh.edu.ht";
        END IF;
        IF EXISTS (SELECT 1 FROM pg_user WHERE usename = 'gestionnaire_informatique@ueh.edu.ht') THEN
            DROP USER "gestionnaire_informatique@ueh.edu.ht";
        END IF;
        IF EXISTS (SELECT 1 FROM pg_user WHERE usename = 'consult_user') THEN
            DROP USER consult_user;
        END IF;
        IF EXISTS (SELECT 1 FROM pg_user WHERE usename = 'chcl_admin_user') THEN
            DROP USER chcl_admin_user;
        END IF;
    END$$;

-- 8. Supprimer le schéma
DROP SCHEMA IF EXISTS gestion_emploi_temps CASCADE;

-- 9. Supprimer l’extension
DROP EXTENSION IF EXISTS btree_gist CASCADE;

-- =============================================
-- RESET COMPLET TERMINE
-- =============================================
