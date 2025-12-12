-- =============================================
-- PROJET CHCL - GESTION EMPLOIS DU TEMPS
-- SCRIPT COMPLET ET CORRIGE (DDL, DCL, DML, TCL)
-- ============================================
-- SECURITE: Arrêter le script immédiatement si une erreur survient
-- \set ON_ERROR_STOP on

-- =============================================
-- PHASE 1 : DDL - STRUCTURE DE LA BASE
-- (Creation des tables, contraintes, index et vues)
-- =============================================

-- Schema principal
CREATE SCHEMA IF NOT EXISTS gestion_emploi_temps;
SET search_path TO gestion_emploi_temps;

-- Extension pour les contraintes d'exclusion
CREATE EXTENSION IF NOT EXISTS btree_gist;


-- Table des programmes/departements
CREATE TABLE programmes
(
    id         SERIAL PRIMARY KEY,
    nom        VARCHAR(100) NOT NULL UNIQUE,
    faculte    VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Table des batiments
CREATE TABLE batiments
(
    id            SERIAL PRIMARY KEY,
    nom           VARCHAR(100) NOT NULL UNIQUE,
    nombre_etages INTEGER DEFAULT 3 CHECK (nombre_etages > 0)
);

-- Table des salles
CREATE TABLE salles
(
    id          SERIAL PRIMARY KEY,
    batiment_id INTEGER     NOT NULL REFERENCES batiments (id) ON DELETE CASCADE,
    etage       INTEGER     NOT NULL CHECK (etage >= 0),
    numero      VARCHAR(20) NOT NULL,
    type_salle  VARCHAR(50) NOT NULL CHECK (type_salle IN ('labo', 'cours', 'td', 'tp')),
    capacite    INTEGER     NOT NULL CHECK (capacite > 0),
    statut      VARCHAR(20) DEFAULT 'disponible' CHECK (statut IN ('disponible', 'occupee', 'maintenance', 'reservee')),
    created_at  TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_salle_batiment UNIQUE (batiment_id, numero)
);

-- Table des professeurs
CREATE TABLE professeurs
(
    id            SERIAL PRIMARY KEY,
    code          VARCHAR(20) UNIQUE  NOT NULL,
    nom           VARCHAR(50)         NOT NULL,
    prenom        VARCHAR(50)         NOT NULL,
    sexe          CHAR(1) CHECK (sexe IN ('M', 'F', 'A')),
    email         VARCHAR(100) UNIQUE NOT NULL CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
    telephone     VARCHAR(20),
    programmes_id INTEGER             NOT NULL REFERENCES programmes (id),
    date_embauche DATE,
    actif         BOOLEAN   DEFAULT TRUE,
    created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Table des matieres
CREATE TABLE matieres
(
    id                   SERIAL PRIMARY KEY,
    code_matiere         VARCHAR(20) UNIQUE NOT NULL,
    nom                  VARCHAR(200)       NOT NULL,
    credits              INTEGER            NOT NULL CHECK (credits BETWEEN 1 AND 6),
    volume_horaire_total INTEGER            NOT NULL CHECK (volume_horaire_total > 0),
    programmes_id        INTEGER            NOT NULL REFERENCES programmes (id),
    semestre             INTEGER CHECK (semestre IN (1, 2)),
    annee_academique     VARCHAR(9)         NOT NULL,
    prerequis            TEXT,
    created_at           TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Table des creneaux horaires
CREATE TABLE creneaux_horaires
(
    id            SERIAL PRIMARY KEY,
    professeur_id INTEGER REFERENCES professeurs (id) ON DELETE SET NULL, -- Peut etre NULL pour indisponibilite ou absence de prof
    matiere_id    INTEGER REFERENCES matieres (id) ON DELETE CASCADE,
    salle_id      INTEGER REFERENCES salles (id) ON DELETE SET NULL, -- Peut etre NULL pour creneau en ligne
    jour_semaine  INTEGER     NOT NULL CHECK (jour_semaine BETWEEN 1 AND 6),
    heure_debut   TIME        NOT NULL,
    heure_fin     TIME        NOT NULL,
    date_debut    DATE        NOT NULL,
    date_fin      DATE        NOT NULL,
    type_seance   VARCHAR(20) NOT NULL CHECK (type_seance IN
                                              ('cours', 'td', 'tp', 'examen', 'soutenance', 'indisponible')),
    statut        VARCHAR(20) DEFAULT 'planifie' CHECK (statut IN ('planifie', 'confirme', 'annule', 'reporte')),
    notes         TEXT,
    created_at    TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,

    -- Contraintes de coherence
    CONSTRAINT check_heure_coherente CHECK (heure_debut < heure_fin),
    CONSTRAINT check_dates_coherentes CHECK (date_debut <= date_fin),
    CONSTRAINT check_duree_max CHECK (EXTRACT(EPOCH FROM (heure_fin - heure_debut)) <= 5 * 3600),
    CONSTRAINT check_duree_min CHECK (EXTRACT(EPOCH FROM (heure_fin - heure_debut)) >= 30 * 60),

    -- Contraintes pour eviter les chevauchements (necessite l'extension btree_gist)
    CONSTRAINT no_chevauchment_salle
        EXCLUDE USING gist (
        salle_id WITH =,
        jour_semaine WITH =,
        tsrange(
                (date_debut + heure_debut)::timestamp,
                (date_debut + heure_fin)::timestamp
        ) WITH &&
        ) WHERE (statut IN ('planifie', 'confirme') AND salle_id IS NOT NULL),

    CONSTRAINT no_chevauchment_professeur
        EXCLUDE USING gist (
        professeur_id WITH =,
        jour_semaine WITH =,
        tsrange(
                (date_debut + heure_debut)::timestamp,
                (date_debut + heure_fin)::timestamp
        ) WITH &&
        ) WHERE (statut IN ('planifie', 'confirme') AND professeur_id IS NOT NULL)
);

-- Table des affectations professeurs/matieres
CREATE TABLE affectations_professeurs
(
    id                SERIAL PRIMARY KEY,
    professeur_id     INTEGER    NOT NULL REFERENCES professeurs (id) ON DELETE CASCADE,
    matiere_id        INTEGER    NOT NULL REFERENCES matieres (id) ON DELETE CASCADE,
    annee_academique  VARCHAR(9) NOT NULL,
    semestre          INTEGER CHECK (semestre IN (1, 2)),
    role              VARCHAR(50) DEFAULT 'responsable' CHECK (role IN ('responsable', 'intervenant', 'assistant')),
    heures_attribuees INTEGER,
    CONSTRAINT uq_affectation UNIQUE (professeur_id, matiere_id, annee_academique, semestre)
);

-- =============================================
-- INDEX POUR L'OPTIMISATION (DDL)
-- =============================================

-- Index pour les recherches frequentes
CREATE INDEX idx_professeurs_nom ON professeurs (nom, prenom);
CREATE INDEX idx_professeurs_email ON professeurs (email);
CREATE INDEX idx_professeurs_programme ON professeurs (programmes_id);

CREATE INDEX idx_matieres_code ON matieres (code_matiere);
CREATE INDEX idx_matieres_programme ON matieres (programmes_id);
CREATE INDEX idx_matieres_semestre ON matieres (semestre, annee_academique);

CREATE INDEX idx_creneaux_date ON creneaux_horaires (date_debut, date_fin);
CREATE INDEX idx_creneaux_professeur ON creneaux_horaires (professeur_id, jour_semaine);
CREATE INDEX idx_creneaux_salle ON creneaux_horaires (salle_id, jour_semaine);
CREATE INDEX idx_creneaux_statut ON creneaux_horaires (statut);
CREATE INDEX idx_creneaux_matiere ON creneaux_horaires (matiere_id);

CREATE INDEX idx_affectations_prof_matiere ON affectations_professeurs (professeur_id, matiere_id);
CREATE INDEX idx_salles_batiment ON salles (batiment_id, type_salle);

-- =============================================
-- VUES POUR FACILITER LES REQUETES (DDL)
-- =============================================

-- Vue pour l'emploi du temps hebdomadaire des professeurs
CREATE OR REPLACE VIEW v_emploi_temps_professeurs AS
SELECT p.code                   AS code_professeur,
       p.nom || ' ' || p.prenom AS professeur,
       m.code_matiere,
       m.nom                    AS matiere,
       CASE ch.jour_semaine
           WHEN 1 THEN 'Lundi'
           WHEN 2 THEN 'Mardi'
           WHEN 3 THEN 'Mercredi'
           WHEN 4 THEN 'Jeudi'
           WHEN 5 THEN 'Vendredi'
           WHEN 6 THEN 'Samedi'
           END                  AS jour,
       ch.heure_debut,
       ch.heure_fin,
       ch.type_seance,
       s.numero                 AS salle,
       b.nom                    AS batiment,
       ch.date_debut,
       ch.statut
FROM creneaux_horaires ch
         LEFT JOIN professeurs p ON ch.professeur_id = p.id
         LEFT JOIN matieres m ON ch.matiere_id = m.id
         LEFT JOIN salles s ON ch.salle_id = s.id
         LEFT JOIN batiments b ON s.batiment_id = b.id
WHERE ch.statut IN ('planifie', 'confirme')
ORDER BY p.nom, ch.jour_semaine, ch.heure_debut;

-- Vue pour la disponibilite des salles
CREATE OR REPLACE VIEW v_disponibilite_salles AS
SELECT s.id,
       b.nom                                        AS batiment,
       s.etage,
       s.numero,
       s.type_salle,
       s.capacite,
       s.statut,
       COUNT(ch.id)                                 AS nombre_creneaux_jour,
       COALESCE(MIN(ch.heure_debut), '08:00'::TIME) AS prochaine_occupation
FROM salles s
         JOIN batiments b ON s.batiment_id = b.id
         LEFT JOIN creneaux_horaires ch ON s.id = ch.salle_id
    AND ch.jour_semaine = EXTRACT(ISODOW FROM CURRENT_DATE)
    AND ch.statut IN ('planifie', 'confirme')
    AND ch.date_debut <= CURRENT_DATE
    AND ch.date_fin >= CURRENT_DATE
GROUP BY s.id, b.nom, s.etage, s.numero, s.type_salle, s.capacite, s.statut;

-- Vue pour les statistiques des professeurs
CREATE OR REPLACE VIEW v_statistiques_professeurs AS
SELECT p.id,
       p.code,
       p.nom || ' ' || p.prenom                                        AS professeur,
       pr.nom                                                          AS programme,
       COUNT(DISTINCT ap.matiere_id)                                   AS nombre_matieres_affectees,
       SUM(ap.heures_attribuees)                                       AS total_heures_attribuees,
       COUNT(ch.id)                                                    AS nombre_creneaux_planifies,
       SUM(EXTRACT(EPOCH FROM (ch.heure_fin - ch.heure_debut)) / 3600) AS heures_planifiees
FROM professeurs p
         JOIN programmes pr ON p.programmes_id = pr.id
         LEFT JOIN affectations_professeurs ap ON p.id = ap.professeur_id
    AND ap.annee_academique = '2024-2025'
         LEFT JOIN creneaux_horaires ch ON p.id = ch.professeur_id
    AND ch.statut IN ('planifie', 'confirme')
GROUP BY p.id, p.code, p.nom, p.prenom, pr.nom;

-- =============================================
-- FONCTIONS ET TRIGGERS (DDL)
-- =============================================

-- Fonction pour mettre a jour le timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
    RETURNS TRIGGER AS
$$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger pour les creneaux horaires
CREATE TRIGGER trigger_update_creneaux_timestamp
    BEFORE UPDATE
    ON creneaux_horaires
    FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

-- Fonction pour verifier la disponibilite
CREATE OR REPLACE FUNCTION verifier_disponibilite(
    p_professeur_id INTEGER,
    p_salle_id INTEGER,
    p_jour_semaine INTEGER,
    p_heure_debut TIME,
    p_heure_fin TIME,
    p_date DATE
)
    RETURNS TABLE
            (
                professeur_disponible BOOLEAN,
                salle_disponible      BOOLEAN,
                message               TEXT
            )
AS
$$
DECLARE
    v_prof_occupe  BOOLEAN;
    v_salle_occupe BOOLEAN;
BEGIN
    -- Verifier si le professeur est disponible
    SELECT EXISTS (SELECT 1
                   FROM creneaux_horaires
                   WHERE professeur_id = p_professeur_id
                     AND jour_semaine = p_jour_semaine
                     AND date_debut <= p_date
                     AND date_fin >= p_date
                     AND statut IN ('planifie', 'confirme')
                     AND (p_heure_debut, p_heure_fin) OVERLAPS (heure_debut, heure_fin))
    INTO v_prof_occupe;

    -- Verifier si la salle est disponible (si salle_id est fourni)
    IF p_salle_id IS NOT NULL THEN
        SELECT EXISTS (SELECT 1
                       FROM creneaux_horaires
                       WHERE salle_id = p_salle_id
                         AND jour_semaine = p_jour_semaine
                         AND date_debut <= p_date
                         AND date_fin >= p_date
                         AND statut IN ('planifie', 'confirme')
                         AND (p_heure_debut, p_heure_fin) OVERLAPS (heure_debut, heure_fin))
        INTO v_salle_occupe;
    ELSE
        v_salle_occupe := FALSE; -- On considere la salle disponible si non specifiee (e.g. cours en ligne)
    END IF;


    RETURN QUERY
        SELECT NOT v_prof_occupe  AS professeur_disponible,
               NOT v_salle_occupe AS salle_disponible,
               CASE
                   WHEN v_prof_occupe AND v_salle_occupe THEN 'Professeur et salle occupes'
                   WHEN v_prof_occupe THEN 'Professeur occupe'
                   WHEN v_salle_occupe THEN 'Salle occupee'
                   ELSE 'Disponible'
                   END            AS message;
END;
$$ LANGUAGE plpgsql;


-- =============================================
-- PHASE 2 : DCL - GESTION DES ROLES ET PRIVILEGES
-- =============================================

-- Role administrateur systeme CHCL
CREATE ROLE chcl_admin WITH
    LOGIN
    NOSUPERUSER
    INHERIT
    NOCREATEDB
    NOCREATEROLE
    NOREPLICATION
    CONNECTION LIMIT 10
    PASSWORD 'bsbs'
    VALID UNTIL '2026-12-31';

COMMENT ON ROLE chcl_admin IS 'Administrateur systeme de la base de donnees CHCL';

-- Role gestionnaire (chef de departement, responsable pedagogique)
CREATE ROLE gestionnaire WITH
    LOGIN
    NOSUPERUSER
    INHERIT
    NOCREATEDB
    NOCREATEROLE
    NOREPLICATION
    CONNECTION LIMIT 20
    PASSWORD 'bsbs';

COMMENT ON ROLE gestionnaire IS 'Gestionnaire pedagogique CHCL';

-- Role professeur
CREATE ROLE professeur_role WITH
    LOGIN
    NOSUPERUSER
    INHERIT
    NOCREATEDB
    NOCREATEROLE
    NOREPLICATION
    CONNECTION LIMIT 50
    PASSWORD 'bsbs';

COMMENT ON ROLE professeur_role IS 'Role generique pour tous les professeurs';

-- Role consultation
CREATE ROLE consultation WITH
    LOGIN
    NOSUPERUSER
    INHERIT
    NOCREATEDB
    NOCREATEROLE
    NOREPLICATION
    CONNECTION LIMIT 100
    PASSWORD 'bsbs';

COMMENT ON ROLE consultation IS 'Role pour consultation seule des emplois du temps';

-- ATTRIBUTION DES PRIVILEGES

-- Privileges pour le role gestionnaire
GRANT USAGE ON SCHEMA gestion_emploi_temps TO gestionnaire;
GRANT SELECT, INSERT, UPDATE, DELETE ON
    professeurs, matieres, creneaux_horaires, affectations_professeurs, salles, batiments, programmes
    TO gestionnaire;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA gestion_emploi_temps TO gestionnaire;
GRANT SELECT ON v_emploi_temps_professeurs, v_statistiques_professeurs TO gestionnaire; -- Acces aux vues publiques
GRANT EXECUTE ON FUNCTION verifier_disponibilite(INTEGER, INTEGER, INTEGER, TIME, TIME, DATE) TO gestionnaire; -- Ajout de l'argument type

-- Privileges pour le role professeur
GRANT USAGE ON SCHEMA gestion_emploi_temps TO professeur_role;
GRANT SELECT ON
    professeurs, matieres, creneaux_horaires, affectations_professeurs, salles, batiments, programmes,
    v_emploi_temps_professeurs, v_statistiques_professeurs, v_disponibilite_salles
    TO professeur_role;
GRANT UPDATE (notes, statut) ON creneaux_horaires TO professeur_role; -- Limite l'update
GRANT EXECUTE ON FUNCTION verifier_disponibilite(INTEGER, INTEGER, INTEGER, TIME, TIME, DATE) TO professeur_role; -- Ajout de l'argument type

-- Privileges pour le role consultation
GRANT USAGE ON SCHEMA gestion_emploi_temps TO consultation;
GRANT SELECT ON
    v_emploi_temps_professeurs, v_disponibilite_salles,
    professeurs, matieres, programmes, salles, batiments
    TO consultation;

-- RLS : Activer et definir les politiques
ALTER TABLE professeurs ENABLE ROW LEVEL SECURITY;
ALTER TABLE creneaux_horaires ENABLE ROW LEVEL SECURITY;
ALTER TABLE affectations_professeurs ENABLE ROW LEVEL SECURITY;
ALTER TABLE matieres ENABLE ROW LEVEL SECURITY;

-- 1. Politique pour les professeurs : ne voir que leurs propres donnees (RLS)
CREATE POLICY professeur_own_data ON professeurs
    FOR SELECT TO professeur_role
    USING (email = current_user OR code = SPLIT_PART(current_user, '_', 2));

CREATE POLICY professeur_own_creneaux ON creneaux_horaires
    FOR ALL TO professeur_role
    USING (professeur_id IN (SELECT id FROM professeurs WHERE email = current_user OR code = SPLIT_PART(current_user, '_', 2)));

CREATE POLICY professeur_own_affectations ON affectations_professeurs
    FOR SELECT TO professeur_role
    USING (professeur_id IN (SELECT id FROM professeurs WHERE email = current_user OR code = SPLIT_PART(current_user, '_', 2)));

-- 2. Politique pour les gestionnaires : acces a leur programme (RLS)
CREATE POLICY gestionnaire_programme_data ON professeurs
    FOR SELECT TO gestionnaire
    USING (programmes_id IN (SELECT id FROM programmes WHERE nom LIKE '%' || SPLIT_PART(current_user, '_', 2) || '%'));

CREATE POLICY gestionnaire_programme_matieres ON matieres
    FOR ALL TO gestionnaire
    USING (programmes_id IN (SELECT id FROM programmes WHERE nom LIKE '%' || SPLIT_PART(current_user, '_', 2) || '%'));

CREATE POLICY gestionnaire_programme_creneaux ON creneaux_horaires
    FOR SELECT TO gestionnaire
    USING (professeur_id IN (SELECT id FROM professeurs WHERE programmes_id IN (SELECT id FROM programmes WHERE nom LIKE '%' || SPLIT_PART(current_user, '_', 2) || '%')));

-- 3. Politique pour la consultation : seulement les donnees actives (RLS)
CREATE POLICY consultation_read_only ON professeurs
    FOR SELECT TO consultation
    USING (actif = true);

CREATE POLICY consultation_active_creneaux ON creneaux_horaires
    FOR SELECT TO consultation
    USING (statut IN ('planifie', 'confirme'));

-- Vues securisees pour les professeurs
CREATE OR REPLACE VIEW v_mes_creneaux AS
SELECT ch.id AS creneau_id, m.nom AS matiere_nom, ch.statut, ch.type_seance, ch.date_debut, ch.date_fin, s.numero AS salle_numero, b.nom AS batiment_nom
FROM creneaux_horaires ch
         LEFT JOIN matieres m ON ch.matiere_id = m.id
         LEFT JOIN salles s ON ch.salle_id = s.id
         LEFT JOIN batiments b ON s.batiment_id = b.id
WHERE ch.professeur_id IN (SELECT id
                           FROM professeurs
                           WHERE email = current_user OR code = SPLIT_PART(current_user, '_', 2));

GRANT SELECT ON v_mes_creneaux TO professeur_role;


-- FONCTIONS SECURISEES

-- Fonction pour qu'un professeur puisse ajouter ses indisponibilites
CREATE OR REPLACE FUNCTION ajouter_indisponibilite(
    p_jour_semaine INTEGER,
    p_heure_debut TIME,
    p_heure_fin TIME,
    p_date_debut DATE,
    p_date_fin DATE,
    p_raison TEXT DEFAULT 'Indisponibilite'
) RETURNS INTEGER AS
$$
DECLARE
    v_professeur_id INTEGER;
    v_creneau_id    INTEGER;
    v_prof_dispo BOOLEAN;
    v_salle_dispo BOOLEAN;
    v_dispo_msg TEXT;
BEGIN
    -- Verifier que l'utilisateur est un professeur
    IF NOT pg_has_role(current_user, 'professeur_role', 'MEMBER') THEN
        RAISE EXCEPTION 'Seuls les professeurs peuvent declarer des indisponibilites';
    END IF;

    -- Trouver l'ID du professeur
    SELECT id INTO v_professeur_id
    FROM professeurs
    WHERE email = current_user OR code = SPLIT_PART(current_user, '_', 2);

    IF v_professeur_id IS NULL THEN
        RAISE EXCEPTION 'Professeur non trouve';
    END IF;

    -- Verifier la disponibilite
    SELECT professeur_disponible, salle_disponible, message
    INTO v_prof_dispo, v_salle_dispo, v_dispo_msg
    FROM verifier_disponibilite(v_professeur_id, NULL, p_jour_semaine, p_heure_debut, p_heure_fin, p_date_debut);

    IF NOT v_prof_dispo THEN
        RAISE EXCEPTION 'Le professeur a deja un creneau a ce moment';
    END IF;

    -- Inserer l'indisponibilite (pas de matiere_id ou salle_id necessaire pour l'indisponibilite)
    INSERT INTO creneaux_horaires (professeur_id, matiere_id, salle_id,
                                   jour_semaine, heure_debut, heure_fin,
                                   date_debut, date_fin, type_seance, statut, notes)
    VALUES (v_professeur_id, NULL, NULL,
            p_jour_semaine, p_heure_debut, p_heure_fin,
            p_date_debut, p_date_fin, 'indisponible', 'confirme',
            p_raison)
    RETURNING id INTO v_creneau_id;

    RETURN v_creneau_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION ajouter_indisponibilite(INTEGER, TIME, TIME, DATE, DATE, TEXT) TO professeur_role;


-- Fonction securisee pour modifier un creneau (utilisee par le professeur)
CREATE OR REPLACE FUNCTION modifier_creneau_professeur(
    p_creneau_id INTEGER,
    p_notes TEXT DEFAULT NULL,
    p_statut VARCHAR(20) DEFAULT NULL
) RETURNS BOOLEAN AS
$$
DECLARE
    v_professeur_id         INTEGER;
    v_current_professeur_id INTEGER;
BEGIN
    -- Verifier l'appartenance du creneau
    SELECT professeur_id INTO v_professeur_id
    FROM creneaux_horaires
    WHERE id = p_creneau_id;

    -- Trouver l'ID du professeur connecte
    SELECT id INTO v_current_professeur_id
    FROM professeurs
    WHERE email = current_user OR code = SPLIT_PART(current_user, '_', 2);

    -- Verifier que le professeur modifie son propre creneau
    IF v_professeur_id IS NULL OR v_professeur_id != v_current_professeur_id THEN
        RAISE EXCEPTION 'Vous ne pouvez modifier que vos propres creneaux planifies';
    END IF;

    -- Mettre a jour
    UPDATE creneaux_horaires
    SET notes      = COALESCE(p_notes, notes),
        statut     = COALESCE(p_statut, statut),
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_creneau_id;

    RETURN FOUND;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION modifier_creneau_professeur(INTEGER, TEXT, VARCHAR) TO professeur_role;


-- =============================================
-- PHASE 3 : DML - INSERTION ET REQUETES
-- =============================================

-- CREATION D'UTILISATEURS DE TEST

-- Revocation des anciens users si le script est execute plusieurs fois
DO $$
    BEGIN
        IF EXISTS (SELECT 1 FROM pg_user WHERE usename = 'pierre_michel.augustin@ueh.edu.ht') THEN
            REVOKE professeur_role FROM "pierre_michel.augustin@ueh.edu.ht";
            DROP USER "pierre_michel.augustin@ueh.edu.ht";
        END IF;
        IF EXISTS (SELECT 1 FROM pg_user WHERE usename = 'gestionnaire_informatique@ueh.edu.ht') THEN
            REVOKE gestionnaire FROM "gestionnaire_informatique@ueh.edu.ht";
            DROP USER "gestionnaire_informatique@ueh.edu.ht";
        END IF;
        IF EXISTS (SELECT 1 FROM pg_user WHERE usename = 'consult_user') THEN
            REVOKE consultation FROM consult_user;
            DROP USER consult_user;
        END IF;
        IF EXISTS (SELECT 1 FROM pg_user WHERE usename = 'chcl_admin_user') THEN
            REVOKE chcl_admin FROM chcl_admin_user;
            DROP USER chcl_admin_user;
        END IF;
    EXCEPTION WHEN others THEN
        NULL;
    END$$;

-- PROFESSEUR
CREATE USER "pierre_michel.augustin@ueh.edu.ht" WITH PASSWORD 'bsbs';
GRANT professeur_role TO "pierre_michel.augustin@ueh.edu.ht";

-- GESTIONNAIRE (Informatique, le 'informatique' est utilise pour le RLS via SPLIT_PART)
CREATE USER "gestionnaire_informatique@ueh.edu.ht" WITH PASSWORD 'bsbs';
GRANT gestionnaire TO "gestionnaire_informatique@ueh.edu.ht";

-- CONSULTATION
CREATE USER consult_user WITH PASSWORD 'bsbs';
GRANT consultation TO consult_user;

-- ADMIN
CREATE USER chcl_admin_user WITH PASSWORD 'pass';
GRANT chcl_admin TO chcl_admin_user;


-- 1. INSERTION DES PROGRAMMES/DEPARTEMENTS
INSERT INTO programmes (nom, faculte)
VALUES ('Informatique', 'Sciences et Technologies'),
       ('Mathematiques', 'Sciences de l''education'),
       ('Genie', 'Sciences et Technologies'),
       ('Environnement', 'FSTEAT'),
       ('Medecine', 'FSS');

-- 2. INSERTION DES BATIMENTS
INSERT INTO batiments (nom, nombre_etages)
VALUES ('A', 3),
       ('B', 3),
       ('C', 3);

-- 3. INSERTION DES SALLES
INSERT INTO salles (batiment_id, etage, numero, type_salle, capacite, statut)
VALUES
    (1, 0, '101', 'cours', 50, 'disponible'),
    (1, 0, '102', 'cours', 45, 'maintenance'),
    (1, 1, '201', 'td', 30, 'disponible'),
    (1, 1, '202', 'td', 25, 'maintenance'),
    (1, 2, '301', 'labo', 20, 'disponible'),
    (1, 2, '302', 'labo', 20, 'maintenance'),
    (2, 0, '103', 'labo', 15, 'disponible'),
    (2, 0, '104', 'labo', 15, 'occupee'),
    (2, 1, '203', 'tp', 25, 'disponible'),
    (2, 1, '204', 'tp', 25, 'disponible'),
    (3, 0, '105', 'cours', 100, 'disponible'),
    (3, 0, '106', 'cours', 80, 'occupee'),
    (3, 1, '205', 'cours', 60, 'disponible');

-- 4. INSERTION DES PROFESSEURS
INSERT INTO professeurs (code, nom, prenom, sexe, email, telephone, programmes_id, date_embauche, actif)
VALUES
    ('PAM', 'AUGUSTIN', 'Pierre Michel', 'M', 'pierre_michel.augustin@ueh.edu.ht', '3611-1111', 1, '2015-09-01', true),
    ('JP', 'PIERRE', 'Jaures', 'M', 'jaures.pierre@ueh.edu.ht', '3611-1112', 1, '2018-03-15', true),
    ('PAN', 'PIERRE', 'Andy', 'M', 'andy.pierre@chcl.edu.ht', '3611-1113', 1, '2020-10-01', true),
    ('PLW', 'PIERRE-LOUIS', 'Wilvens', 'M', 'wilvens.pierre-louis@chcl.edu.ht', '3611-1114', 2, '2012-09-01', true),
    ('NS', 'SYFRA', 'Nesly', 'M', 'nesly.syfra@chcl.edu.ht', '3611-1115', 2, '2016-02-20', true),
    ('LR', 'Rousseau', 'Luc', 'M', 'luc.rousseau@chcl.edu.ht', '3611-1116', 3, '2014-09-01', true),
    ('TL', 'Lefebvre', 'Thomas', 'M', 'thomas.lefebvre@chcl.edu.ht', '3611-1118', 4, '2017-04-01', true),
    ('IP', 'Petit', 'Isabelle', 'F', 'isabelle.petit@chcl.edu.ht', '3611-1119', 5, '2013-09-01', true),
    ('NR', 'Roux', 'Nicolas', 'M', 'nicolas.roux@chcl.edu.ht', '3611-1120', 5, '2021-09-01', true),
    ('PROF_INACTIF', 'ARCHIVE', 'Utilisateur', 'A', 'archive.user@chcl.edu.ht', '0000-0000', 1, '2000-01-01', false);

-- 5. INSERTION DES MATIERES
INSERT INTO matieres (code_matiere, nom, credits, volume_horaire_total, programmes_id, semestre, annee_academique, prerequis)
VALUES
    ('INF101', 'Introduction a la programmation', 6, 60, 1, 1, '2024-2025', 'Aucun'),
    ('INF102', 'Algorithmique et structures de donnees', 5, 50, 1, 1, '2024-2025', 'INF101'),
    ('INF103', 'Architecture des ordinateurs', 4, 40, 1, 1, '2024-2025', 'Aucun'),
    ('INF201', 'Bases de donnees', 6, 60, 1, 2, '2024-2025', 'INF101'),
    ('INF202', 'Systemes d''exploitation', 5, 50, 1, 2, '2024-2025', 'INF103'),
    ('INF203', 'Reseaux informatiques', 4, 40, 1, 2, '2024-2025', 'INF102'),
    ('MAT101', 'Algebre lineaire', 6, 60, 2, 1, '2024-2025', 'Aucun'),
    ('MAT102', 'Analyse 1', 6, 60, 2, 1, '2024-2025', 'Aucun'),
    ('PHY101', 'Mecanique du point', 6, 60, 3, 1, '2024-2025', 'Aucun'),
    ('PHY102', 'Electricite et magnetisme', 5, 50, 3, 1, '2024-2025', 'Aucun');


-- 6. INSERTION DES AFFECTATIONS PROFESSEURS/MATIERES
INSERT INTO affectations_professeurs (professeur_id, matiere_id, annee_academique, semestre, role, heures_attribuees)
VALUES
    (1, 1, '2024-2025', 1, 'responsable', 30), -- PAM (prof 1) -> INF101 (matiere 1)
    (1, 4, '2024-2025', 2, 'responsable', 30), -- PAM (prof 1) -> INF201 (matiere 4)
    (2, 2, '2024-2025', 1, 'responsable', 25), -- JP (prof 2) -> INF102 (matiere 2)
    (3, 3, '2024-2025', 1, 'responsable', 20), -- PAN (prof 3) -> INF103 (matiere 3)
    (4, 7, '2024-2025', 1, 'responsable', 30), -- PLW (prof 4) -> MAT101 (matiere 7)
    (5, 8, '2024-2025', 1, 'responsable', 30); -- NS (prof 5) -> MAT102 (matiere 8)


-- 7. INSERTION DES CRENEAUX HORAIRES (Semestre 1)
-- Lundi (1)
INSERT INTO creneaux_horaires (professeur_id, matiere_id, salle_id, jour_semaine, heure_debut, heure_fin, date_debut, date_fin, type_seance, statut)
VALUES (1, 1, 1, 1, '08:00', '10:00', '2024-09-02', '2025-01-20', 'cours', 'confirme'), -- PAM/INF101/S101
       (4, 7, 11, 1, '10:15', '12:15', '2024-09-02', '2025-01-20', 'cours', 'confirme'), -- PLW/MAT101/S105
       (6, 9, 12, 1, '13:30', '15:30', '2024-09-02', '2025-01-20', 'cours', 'confirme'); -- LR/PHY101/S106

-- Mardi (2)
INSERT INTO creneaux_horaires (professeur_id, matiere_id, salle_id, jour_semaine, heure_debut, heure_fin, date_debut, date_fin, type_seance, statut)
VALUES (2, 2, 2, 2, '08:00', '10:00', '2024-09-03', '2025-01-21', 'cours', 'confirme'), -- JP/INF102/S102
       (5, 8, 11, 2, '10:15', '12:15', '2024-09-03', '2025-01-21', 'cours', 'confirme'), -- NS/MAT102/S105
       (7, 10, 12, 2, '13:30', '15:30', '2024-09-03', '2025-01-21', 'cours', 'confirme'); -- TL/PHY102/S106

-- Mercredi (3)
INSERT INTO creneaux_horaires (professeur_id, matiere_id, salle_id, jour_semaine, heure_debut, heure_fin, date_debut, date_fin, type_seance, statut)
VALUES (3, 3, 3, 3, '08:00', '10:00', '2024-09-04', '2025-01-22', 'cours', 'confirme'), -- PAN/INF103/S201
       (1, 1, 5, 3, '13:30', '16:30', '2024-09-04', '2025-01-22', 'tp', 'confirme'), -- PAM/INF101/S301
       (2, 2, 6, 3, '13:30', '16:30', '2024-09-04', '2025-01-22', 'tp', 'confirme'); -- JP/INF102/S302

-- Indisponibilite du professeur 1 (PAM) pour test RLS/Fonction
INSERT INTO creneaux_horaires (professeur_id, matiere_id, salle_id, jour_semaine, heure_debut, heure_fin, date_debut, date_fin, type_seance, statut, notes)
VALUES (1, NULL, NULL, 4, '08:00', '11:00', '2024-12-01', '2025-01-30', 'indisponible', 'confirme', 'Recherche');


-- REQUETES COMPLEXES AVEC JOINTURES ET AGREGATIONS (DML)

-- 1. REQUETE : Emploi du temps complet d'un professeur
SELECT p.nom || ' ' || p.prenom AS professeur, m.nom AS matiere,
       CASE ch.jour_semaine WHEN 1 THEN 'Lundi' WHEN 2 THEN 'Mardi' WHEN 3 THEN 'Mercredi' WHEN 4 THEN 'Jeudi' WHEN 5 THEN 'Vendredi' WHEN 6 THEN 'Samedi' END AS jour,
       ch.heure_debut, ch.heure_fin, s.numero AS salle, b.nom AS batiment, ch.type_seance, ch.statut
FROM creneaux_horaires ch
         LEFT JOIN professeurs p ON ch.professeur_id = p.id
         LEFT JOIN matieres m ON ch.matiere_id = m.id
         LEFT JOIN salles s ON ch.salle_id = s.id
         LEFT JOIN batiments b ON s.batiment_id = b.id
WHERE p.code = 'PAM'
  AND ch.statut IN ('planifie', 'confirme')
ORDER BY ch.jour_semaine, ch.heure_debut;

-- 2. REQUETE : Nombre d'heures par professeur et par semaine
SELECT p.code, p.nom || ' ' || p.prenom AS professeur, pr.nom AS programme, COUNT(ch.id) AS nombre_cours_semaine,
       ROUND(SUM(EXTRACT(EPOCH FROM (ch.heure_fin - ch.heure_debut)) / 3600), 1) AS heures_total_semaine
FROM professeurs p
         JOIN programmes pr ON p.programmes_id = pr.id
         LEFT JOIN creneaux_horaires ch ON p.id = ch.professeur_id AND ch.statut IN ('planifie', 'confirme')
GROUP BY p.id, p.code, p.nom, p.prenom, pr.nom
ORDER BY heures_total_semaine DESC;


-- OPERATIONS DE MISE A JOUR ET SUPPRESSION (DML)

-- MISE A JOUR : Reporter un creneau horaire (Salle A202 est en maintenance, id=4)
UPDATE creneaux_horaires
SET statut     = 'reporte',
    notes      = CONCAT(COALESCE(notes, ''), ' Reporte pour cause de maintenance salle A202. '),
    updated_at = CURRENT_TIMESTAMP
WHERE salle_id = 4 -- Salle A202
  AND date_debut >= CURRENT_DATE
RETURNING id, professeur_id, matiere_id, date_debut, statut;

-- SUPPRESSION : Supprimer les creneaux annules de plus d'un mois (Test avec un statut 'annule')
INSERT INTO creneaux_horaires (professeur_id, matiere_id, salle_id, jour_semaine, heure_debut, heure_fin, date_debut, date_fin, type_seance, statut, updated_at)
VALUES (1, 1, 1, 5, '17:00', '18:00', '2024-01-01', '2024-01-01', 'cours', 'annule', CURRENT_DATE - INTERVAL '60 days');

DELETE FROM creneaux_horaires
WHERE statut = 'annule'
  AND updated_at < CURRENT_DATE - INTERVAL '30 days'
RETURNING id, professeur_id, matiere_id, date_debut;

-- SUPPRESSION : Supprimer les affectations d'un professeur inactif (PROF_INACTIF id=10)
DELETE FROM affectations_professeurs
WHERE professeur_id IN (SELECT id FROM professeurs WHERE actif = false)
RETURNING id, professeur_id, matiere_id;

-- =============================================
-- PHASE 4 : TCL - TRANSACTIONS ET PROCEDURES
-- =============================================

-- PROCEDURE STOCKE EN UTILISANT UNE TRANSACTION COMPLEXE
-- Objectif : Planifier une nouvelle matiere avec verification d'affectation et gestion des erreurs (ROLLBACK implicite).

CREATE OR REPLACE FUNCTION planifier_nouveau_cours_transactionnel(
    p_professeur_code VARCHAR,
    p_matiere_code VARCHAR,
    p_salle_numero VARCHAR,
    p_jour_semaine INTEGER,
    p_heure_debut TIME,
    p_heure_fin TIME,
    p_date_debut DATE,
    p_date_fin DATE
)
    RETURNS TEXT AS
$$
DECLARE
    v_prof_id INTEGER;
    v_mat_id  INTEGER;
    v_salle_id INTEGER;
    v_annee_academique VARCHAR(9);
    v_semestre INTEGER;
    v_is_affected BOOLEAN;
    v_prof_dispo BOOLEAN;
    v_salle_dispo BOOLEAN;
    v_dispo_msg TEXT;
    v_message TEXT;
BEGIN
    -- 1. Recuperation des IDs
    SELECT id INTO v_prof_id FROM professeurs WHERE code = p_professeur_code;
    SELECT id, semestre, annee_academique INTO v_mat_id, v_semestre, v_annee_academique FROM matieres WHERE code_matiere = p_matiere_code;
    SELECT s.id INTO v_salle_id FROM salles s JOIN batiments b ON s.batiment_id = b.id WHERE s.numero = p_salle_numero;

    IF v_prof_id IS NULL THEN RAISE EXCEPTION 'Erreur: Professeur (code: %) non trouve.', p_professeur_code; END IF;
    IF v_mat_id IS NULL THEN RAISE EXCEPTION 'Erreur: Matiere (code: %) non trouvee.', p_matiere_code; END IF;
    IF v_salle_id IS NULL THEN RAISE EXCEPTION 'Erreur: Salle (numero: %) non trouvee.', p_salle_numero; END IF;

    -- 2. Verification de l'affectation du professeur a la matiere
    SELECT EXISTS (
        SELECT 1 FROM affectations_professeurs
        WHERE professeur_id = v_prof_id
          AND matiere_id = v_mat_id
          AND annee_academique = v_annee_academique
          AND semestre = v_semestre
    ) INTO v_is_affected;

    IF NOT v_is_affected THEN
        -- L'exception ici entraine un ROLLBACK automatique de la fonction.
        RAISE EXCEPTION 'ERREUR CRITIQUE: Le professeur % n''est pas affecte a la matiere % pour le semestre %.', p_professeur_code, p_matiere_code, v_semestre;
    END IF;

    -- 3. Verification de la disponibilite
    SELECT professeur_disponible, salle_disponible, message
    INTO v_prof_dispo, v_salle_dispo, v_dispo_msg
    FROM verifier_disponibilite(v_prof_id, v_salle_id, p_jour_semaine, p_heure_debut, p_heure_fin, p_date_debut);

    IF NOT v_prof_dispo OR NOT v_salle_dispo THEN
        RAISE EXCEPTION 'ERREUR: Chevauchement d''horaire detecte. Raison: %', v_dispo_msg;
    END IF;

    -- 4. Insertion du creneau si toutes les verifications sont valides
    INSERT INTO creneaux_horaires (professeur_id, matiere_id, salle_id, jour_semaine, heure_debut, heure_fin, date_debut, date_fin, type_seance, statut)
    VALUES (v_prof_id, v_mat_id, v_salle_id, p_jour_semaine, p_heure_debut, p_heure_fin, p_date_debut, p_date_fin, 'cours', 'planifie');

    v_message := 'Succes: Le cours a ete planifie avec succes.';
    RETURN v_message;

EXCEPTION
    WHEN others THEN
        -- Gestion des erreurs et s'assure que le message d'erreur est retourne.
        GET STACKED DIAGNOSTICS v_message = MESSAGE_TEXT;
        v_message := 'Echec de la planification du cours. Raison: ' || v_message;

        RETURN v_message;
END;
$$ LANGUAGE plpgsql;

-- Exemple d'appel (Succes)
SELECT planifier_nouveau_cours_transactionnel(
               'PAM',       -- Professeur affecte a INF101
               'INF101',    -- Matiere affectee
               '102',       -- Salle A102
               5,           -- Vendredi
               '15:00',
               '17:00',
               '2024-09-06',
               '2025-01-24'
       );

-- Exemple d'appel (Echec avec ROLLBACK implicite: Professeur non affecte a la matiere)
SELECT planifier_nouveau_cours_transactionnel(
               'PAM',       -- Professeur affecte a INF101
               'PHY101',    -- Matiere non affectee a PAM
               '102',
               6,           -- Samedi
               '08:00',
               '10:00',
               '2024-09-07',
               '2025-01-25'
       );

