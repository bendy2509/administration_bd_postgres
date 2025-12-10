-- =============================================
-- PROJET CHCL - GESTION EMPLOIS DU TEMPS
-- ============================================

-- =============================================
-- PHASE 1 : DDL - STRUCTURE DE LA BASE
-- =============================================

-- Extension pour les contraintes d'exclusion
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- Schema principal
CREATE SCHEMA IF NOT EXISTS gestion_emploi_temps;
SET search_path TO gestion_emploi_temps;

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
    professeur_id INTEGER     NOT NULL REFERENCES professeurs (id),
    matiere_id    INTEGER     NOT NULL REFERENCES matieres (id),
    salle_id      INTEGER     NOT NULL REFERENCES salles (id),
    jour_semaine  INTEGER     NOT NULL CHECK (jour_semaine BETWEEN 1 AND 6),
    heure_debut   TIME        NOT NULL,
    heure_fin     TIME        NOT NULL,
    date_debut    DATE        NOT NULL,
    date_fin      DATE        NOT NULL,
    type_seance   VARCHAR(20) NOT NULL CHECK (type_seance IN
                                              ('cours', 'td', 'tp', 'examen', 'soutenance')),
    statut        VARCHAR(20) DEFAULT 'planifie' CHECK (statut IN ('planifie', 'confirme', 'annule', 'reporte')),
    notes         TEXT,
    created_at    TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,

    -- Contraintes de coherence
    CONSTRAINT check_heure_coherente CHECK (heure_debut < heure_fin),
    CONSTRAINT check_dates_coherentes CHECK (date_debut <= date_fin),
    CONSTRAINT check_duree_max CHECK (EXTRACT(EPOCH FROM (heure_fin - heure_debut)) <= 5 * 3600),
    CONSTRAINT check_duree_min CHECK (EXTRACT(EPOCH FROM (heure_fin - heure_debut)) >= 30 * 60),

    -- Contraintes pour eviter les chevauchements
    CONSTRAINT no_chevauchment_salle
        EXCLUDE USING gist (
        salle_id WITH =,
        jour_semaine WITH =,
        tsrange(
                (date_debut + heure_debut)::timestamp,
                (date_debut + heure_fin)::timestamp
        ) WITH &&
        ) WHERE (statut IN ('planifie', 'confirme')),

    CONSTRAINT no_chevauchment_professeur
        EXCLUDE USING gist (
        professeur_id WITH =,
        jour_semaine WITH =,
        tsrange(
                (date_debut + heure_debut)::timestamp,
                (date_debut + heure_fin)::timestamp
        ) WITH &&
        ) WHERE (statut IN ('planifie', 'confirme'))
);

-- Table des affectations professeurs/matieres
CREATE TABLE affectations_professeurs
(
    id                SERIAL PRIMARY KEY,
    professeur_id     INTEGER    NOT NULL REFERENCES professeurs (id),
    matiere_id        INTEGER    NOT NULL REFERENCES matieres (id),
    annee_academique  VARCHAR(9) NOT NULL,
    semestre          INTEGER CHECK (semestre IN (1, 2)),
    role              VARCHAR(50) DEFAULT 'responsable' CHECK (role IN ('responsable', 'intervenant', 'assistant')),
    heures_attribuees INTEGER,
    CONSTRAINT uq_affectation UNIQUE (professeur_id, matiere_id, annee_academique, semestre)
);

-- =============================================
-- INDEX POUR L'OPTIMISATION
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
-- VUES POUR FACILITER LES REQUETES
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
         JOIN professeurs p ON ch.professeur_id = p.id
         JOIN matieres m ON ch.matiere_id = m.id
         JOIN salles s ON ch.salle_id = s.id
         JOIN batiments b ON s.batiment_id = b.id
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
       COUNT(ch.id)                                 AS nombre_creneaux,
       COALESCE(MIN(ch.heure_debut), '08:00'::TIME) AS prochaine_disponibilite
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
       COUNT(DISTINCT ap.matiere_id)                                   AS nombre_matieres,
       SUM(ap.heures_attribuees)                                       AS total_heures_attribuees,
       COUNT(ch.id)                                                    AS nombre_creneaux,
       SUM(EXTRACT(EPOCH FROM (ch.heure_fin - ch.heure_debut)) / 3600) AS heures_planifiees
FROM professeurs p
         JOIN programmes pr ON p.programmes_id = pr.id
         LEFT JOIN affectations_professeurs ap ON p.id = ap.professeur_id
    AND ap.annee_academique = '2024-2025'
         LEFT JOIN creneaux_horaires ch ON p.id = ch.professeur_id
    AND ch.statut IN ('planifie', 'confirme')
GROUP BY p.id, p.code, p.nom, p.prenom, pr.nom;

CREATE OR REPLACE VIEW v_calendrier_academique AS
SELECT
    m.code_matiere,
    m.nom AS matiere,
    p.nom AS programme,
    ch.jour_semaine,
    ch.heure_debut,
    ch.heure_fin,
    ch.type_seance,
    s.numero AS salle,
    b.nom AS batiment,
    ch.date_debut,
    ch.date_fin,
    (SELECT COUNT(*)
     FROM creneaux_horaires ch2
     WHERE ch2.matiere_id = m.id
       AND ch2.statut IN ('planifie', 'confirme')) AS total_seances
FROM matieres m
         JOIN programmes p ON m.programmes_id = p.id
         JOIN creneaux_horaires ch ON m.id = ch.matiere_id
         JOIN salles s ON ch.salle_id = s.id
         JOIN batiments b ON s.batiment_id = b.id
WHERE ch.statut IN ('planifie', 'confirme')
ORDER BY m.code_matiere, ch.date_debut;

-- =============================================
-- FONCTIONS ET TRIGGERS
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

-- =============================================
-- FONCTION POUR VERIFIER LA DISPONIBILITE
-- =============================================

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
    -- Vérifier si le professeur est disponible
    SELECT EXISTS (SELECT 1
                   FROM creneaux_horaires
                   WHERE professeur_id = p_professeur_id
                     AND jour_semaine = p_jour_semaine
                     AND date_debut <= p_date
                     AND date_fin >= p_date
                     AND statut IN ('planifie', 'confirme')
                     AND (p_heure_debut, p_heure_fin) OVERLAPS (heure_debut, heure_fin))
    INTO v_prof_occupe;

    -- Verifier si la salle est disponible
    SELECT EXISTS (SELECT 1
                   FROM creneaux_horaires
                   WHERE salle_id = p_salle_id
                     AND jour_semaine = p_jour_semaine
                     AND date_debut <= p_date
                     AND date_fin >= p_date
                     AND statut IN ('planifie', 'confirme')
                     AND (p_heure_debut, p_heure_fin) OVERLAPS (heure_debut, heure_fin))
    INTO v_salle_occupe;

    RETURN QUERY
        SELECT NOT v_prof_occupe  AS professeur_disponible,
               NOT v_salle_occupe AS salle_disponible,
               CASE
                   WHEN v_prof_occupe AND v_salle_occupe THEN 'Professeur et salle occupés'
                   WHEN v_prof_occupe THEN 'Professeur occupé'
                   WHEN v_salle_occupe THEN 'Salle occupée'
                   ELSE 'Disponible'
                   END            AS message;
END;
$$ LANGUAGE plpgsql;


-- =============================================
-- CREATION DES ROLES HIERARCHIQUES
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

-- 3. Role gestionnaire (chef de departement, responsable pedagogique)
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

-- 4. Role professeur
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

-- 5. Role consultation (etudiants, personnel administratif)
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

-- =============================================
-- CREATION D'UTILISATEURS SPECIFIQUES
-- =============================================

-- Administrateurs specifiques
CREATE USER admin_servilus WITH
    PASSWORD 'bsbs'
    IN ROLE chcl_admin
    VALID UNTIL '2026-12-31';

-- =============================================
-- ATTRIBUTION DES PRIVILEGES PAR ROLE
-- =============================================

-- Accorder tous les privileges sur le schema a chcl_admin
GRANT ALL PRIVILEGES ON SCHEMA gestion_emploi_temps TO chcl_admin;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA gestion_emploi_temps TO chcl_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA gestion_emploi_temps TO chcl_admin;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA gestion_emploi_temps TO chcl_admin;
GRANT ALL PRIVILEGES ON ALL PROCEDURES IN SCHEMA gestion_emploi_temps TO chcl_admin;

-- Permettre a chcl_admin de modifier les privileges
GRANT CREATE ON SCHEMA gestion_emploi_temps TO chcl_admin;

-- Privileges pour le role gestionnaire
GRANT USAGE ON SCHEMA gestion_emploi_temps TO gestionnaire;

-- Tables accessibles en lecture/ecriture pour gestionnaire
GRANT SELECT, INSERT, UPDATE, DELETE ON
    professeurs,
    matieres,
    creneaux_horaires,
    affectations_professeurs,
    salles,
    batiments,
    programmes
    TO gestionnaire;

-- Permission d'utiliser les séquences
GRANT USAGE ON ALL SEQUENCES IN SCHEMA gestion_emploi_temps TO gestionnaire;

-- Privilèges pour le rôle professeur
GRANT USAGE ON SCHEMA gestion_emploi_temps TO professeur_role;

-- Tables accessibles en lecture pour professeur
GRANT SELECT ON
    professeurs,
    matieres,
    creneaux_horaires,
    affectations_professeurs,
    salles,
    batiments,
    programmes,
    v_emploi_temps_professeurs,
    v_calendrier_academique,
    v_statistiques_professeurs
    TO professeur_role;

-- Permissions limitées d'écriture pour professeur
GRANT INSERT, UPDATE ON creneaux_horaires TO professeur_role;
GRANT UPDATE (notes, statut) ON creneaux_horaires TO professeur_role;

-- Permission d'exécuter les fonctions
GRANT EXECUTE ON FUNCTION verifier_disponibilite TO professeur_role;

-- Privilèges pour le rôle consultation
GRANT USAGE ON SCHEMA gestion_emploi_temps TO consultation;

-- Tables accessibles en lecture seule pour consultation
GRANT SELECT ON
    v_emploi_temps_professeurs,
    v_calendrier_academique,
    v_disponibilite_salles,
    professeurs,
    matieres,
    programmes,
    salles,
    batiments
    TO consultation;

-- =============================================
-- DOCUMENTATION DES RÔLES ET PRIVILÈGES
-- =============================================

COMMENT ON ROLE chcl_admin IS '
Role: Administrateur CHCL
Permissions:
- Toutes les permissions sur toutes les tables
- Peut creer/modifier/supprimer des objets
- Peut gerer les utilisateurs et les roles
- Acces complet sans restrictions RLS
';

COMMENT ON ROLE gestionnaire IS '
Role: Gestionnaire pedagogique
Permissions:
- Lecture/ecriture sur les tables pedagogiques
- Lecture seule sur les tables d''audit
- Acces restreint a son programme seulement (RLS)
- Peut gerer les creneaux horaires
';

COMMENT ON ROLE professeur_role IS '
Role: Professeur
Permissions:
- Lecture de ses propres donnees
- Modification de ses creneaux horaires
- Declaration d''indisponibilites
- Consultation de l''emploi du temps
- Acces restreint a ses propres donnees (RLS)
';

COMMENT ON ROLE consultation IS '
Role: Consultation
Permissions:
- Lecture seule des donnees actives
- Consultation des emplois du temps
- Consultation des salles disponibles
- Aucun droit d''ecriture
- Filtrage des donnees inactives (RLS)
';


-- =============================================
-- INSERTION DE DONNEES REALISTES
-- Programme: Premiere annee université CHCL
-- Annee academique: 2024-2025
-- =============================================

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
-- Batiment A
(1, 0, '101', 'cours', 50, 'disponible'),
(1, 0, '102', 'cours', 45, 'disponible'),
(1, 1, '201', 'td', 30, 'disponible'),
(1, 1, '202', 'td', 25, 'disponible'),
(1, 2, '206', 'labo', 20, 'disponible'),
(1, 2, '203', 'labo', 20, 'maintenance'),
-- Batiment
(2, 0, '201', 'labo', 15, 'disponible'),
(2, 0, '302', 'labo', 15, 'disponible'),
(2, 1, '101', 'tp', 25, 'disponible'),
(2, 1, '102', 'tp', 25, 'disponible'),
-- Batiment C
(3, 0, '101', 'cours', 100, 'disponible'),
(3, 0, '102', 'cours', 80, 'disponible'),
(3, 1, '201', 'cours', 60, 'disponible');

INSERT INTO professeurs (code, nom, prenom, sexe, email, telephone, programmes_id, date_embauche, actif)
VALUES
-- Conserver les deux premiers avec @ueh.edu.ht
('PAM', 'AUGUSTIN', 'Pierre Michel', 'M', 'pierre.michel@ueh.edu.ht', '3611-1111', 1, '2015-09-01', true),
('JP', 'PIERRE', 'Jaures', 'M', 'jaures.pierre@ueh.edu.ht', '3611-1112', 1, '2018-03-15', true),

-- Tous les autres avec @chcl.edu.ht, format: prenom.nom@chcl.edu.ht
('PAN', 'PIERRE', 'Andy', 'M', 'andy.pierre@chcl.edu.ht', '3611-1113', 1, '2020-10-01', true),
('PIWIL', 'PIERRE-LOUIS', 'Wilvens', 'M', 'wilvens.pierre-louis@chcl.edu.ht', '3611-1114', 2, '2012-09-01', true),
('MAT002', 'SYFRA', 'Nesly', 'M', 'nesly.syfra@chcl.edu.ht', '3611-1115', 2, '2016-02-20', true),
('PHY001', 'Rousseau', 'Luc', 'M', 'luc.rousseau@chcl.edu.ht', '3611-1116', 3, '2014-09-01', true),
('CHI001', 'Lefebvre', 'Thomas', 'M', 'thomas.lefebvre@chcl.edu.ht', '3611-1118', 4, '2017-04-01', true),
('BIO001', 'Petit', 'Isabelle', 'F', 'isabelle.petit@chcl.edu.ht', '3611-1119', 5, '2013-09-01', true),
('BIO002', 'Roux', 'Nicolas', 'M', 'nicolas.roux@chcl.edu.ht', '3611-1120', 5, '2021-09-01', true);

-- 5. INSERTION DES MATIERES
INSERT INTO matieres (code_matiere, nom, credits, volume_horaire_total, programmes_id, semestre, annee_academique,
                      prerequis)
VALUES
-- Informatique - Semestre 1
('INF101', 'Introduction a la programmation', 6, 60, 1, 1, '2024-2025', 'Aucun'),
('INF102', 'Algorithmique et structures de donnees', 5, 50, 1, 1, '2024-2025', 'INF101'),
('INF103', 'Architecture des ordinateurs', 4, 40, 1, 1, '2024-2025', 'Aucun'),
-- Informatique - Semestre 2
('INF201', 'Bases de donnees', 6, 60, 1, 2, '2024-2025', 'INF101'),
('INF202', 'Systèmes d''exploitation', 5, 50, 1, 2, '2024-2025', 'INF103'),
('INF203', 'Réseaux informatiques', 4, 40, 1, 2, '2024-2025', 'INF102'),

-- Mathématiques
('MAT101', 'Algèbre linéaire', 6, 60, 2, 1, '2024-2025', 'Aucun'),
('MAT102', 'Analyse 1', 6, 60, 2, 1, '2024-2025', 'Aucun'),
('MAT201', 'Analyse 2', 6, 60, 2, 2, '2024-2025', 'MAT102'),
('MAT202', 'Probabilités', 5, 50, 2, 2, '2024-2025', 'MAT101'),

-- Physique
('PHY101', 'Mécanique du point', 6, 60, 3, 1, '2024-2025', 'Aucun'),
('PHY102', 'Électricité et magnétisme', 5, 50, 3, 1, '2024-2025', 'Aucun'),
('PHY201', 'Ondes et optique', 6, 60, 3, 2, '2024-2025', 'PHY101'),
('PHY202', 'Thermodynamique', 5, 50, 3, 2, '2024-2025', 'PHY102'),

-- Chimie
('CHI101', 'Chimie générale', 6, 60, 4, 1, '2024-2025', 'Aucun'),
('CHI102', 'Chimie organique 1', 5, 50, 4, 1, '2024-2025', 'CHI101'),
('CHI201', 'Chimie organique 2', 6, 60, 4, 2, '2024-2025', 'CHI102'),
('CHI202', 'Chimie analytique', 5, 50, 4, 2, '2024-2025', 'CHI101'),

-- Biologie
('BIO101', 'Biologie cellulaire', 6, 60, 5, 1, '2024-2025', 'Aucun'),
('BIO102', 'Génétique', 5, 50, 5, 1, '2024-2025', 'BIO101'),
('BIO201', 'Biologie moléculaire', 6, 60, 5, 2, '2024-2025', 'BIO102'),
('BIO202', 'Biochimie', 5, 50, 5, 2, '2024-2025', 'CHI101');

-- 6. INSERTION DES AFFECTATIONS PROFESSEURS/MATIERES
INSERT INTO affectations_professeurs (professeur_id, matiere_id, annee_academique, semestre, role, heures_attribuees)
VALUES
-- Informatique
(1, 1, '2024-2025', 1, 'responsable', 30),
(1, 4, '2024-2025', 2, 'responsable', 30),
(2, 2, '2024-2025', 1, 'responsable', 25),
(2, 5, '2024-2025', 2, 'responsable', 25),
(3, 3, '2024-2025', 1, 'responsable', 20),
(3, 6, '2024-2025', 2, 'responsable', 20),
-- Mathématiques
(4, 7, '2024-2025', 1, 'responsable', 30),
(4, 9, '2024-2025', 2, 'responsable', 30),
(5, 8, '2024-2025', 1, 'responsable', 30),
(5, 10, '2024-2025', 2, 'responsable', 25),
-- Physique
(6, 11, '2024-2025', 1, 'responsable', 30),
(6, 13, '2024-2025', 2, 'responsable', 30),
(7, 12, '2024-2025', 1, 'responsable', 25),
(7, 14, '2024-2025', 2, 'responsable', 25),
-- Chimie
(8, 15, '2024-2025', 1, 'responsable', 30),
(8, 17, '2024-2025', 2, 'responsable', 30),
-- Biologie
(9, 18, '2024-2025', 1, 'responsable', 25),
(9, 20, '2024-2025', 2, 'responsable', 25);

-- 7. INSERTION DES CRENEAUX HORAIRES
-- Semestre 1
-- Lundi (1)
INSERT INTO creneaux_horaires (professeur_id, matiere_id, salle_id, jour_semaine, heure_debut, heure_fin, date_debut,
                               date_fin, type_seance, statut)
VALUES (1, 1, 1, 1, '08:00', '10:00', '2024-09-02', '2025-01-20', 'cours', 'confirme'),
       (4, 7, 11, 1, '10:15', '12:15', '2024-09-02', '2025-01-20', 'cours', 'confirme'),
       (6, 11, 12, 1, '13:30', '15:30', '2024-09-02', '2025-01-20', 'cours', 'confirme'),
       (9, 18, 4, 1, '15:45', '17:45', '2024-09-02', '2025-01-20', 'td', 'confirme');

-- Mardi (2)
INSERT INTO creneaux_horaires (professeur_id, matiere_id, salle_id, jour_semaine, heure_debut, heure_fin, date_debut,
                               date_fin, type_seance, statut)
VALUES (2, 2, 2, 2, '08:00', '10:00', '2024-09-03', '2025-01-21', 'cours', 'confirme'),
       (5, 8, 11, 2, '10:15', '12:15', '2024-09-03', '2025-01-21', 'cours', 'confirme'),
       (7, 12, 12, 2, '13:30', '15:30', '2024-09-03', '2025-01-21', 'cours', 'confirme');

-- Mercredi (3)
INSERT INTO creneaux_horaires (professeur_id, matiere_id, salle_id, jour_semaine, heure_debut, heure_fin, date_debut,
                               date_fin, type_seance, statut)
VALUES (3, 3, 3, 3, '08:00', '10:00', '2024-09-04', '2025-01-22', 'cours', 'confirme'),
       (8, 15, 11, 3, '10:15', '12:15', '2024-09-04', '2025-01-22', 'cours', 'confirme'),
       (1, 1, 7, 3, '13:30', '16:30', '2024-09-04', '2025-01-22', 'tp', 'confirme'),
       (2, 2, 8, 3, '13:30', '16:30', '2024-09-04', '2025-01-22', 'tp', 'confirme');

-- Jeudi (4)
INSERT INTO creneaux_horaires (professeur_id, matiere_id, salle_id, jour_semaine, heure_debut, heure_fin, date_debut,
                               date_fin, type_seance, statut)
VALUES (4, 7, 3, 4, '08:00', '10:00', '2024-09-05', '2025-01-23', 'td', 'confirme'),
       (5, 8, 4, 4, '10:15', '12:15', '2024-09-05', '2025-01-23', 'td', 'confirme'),
       (6, 11, 9, 4, '13:30', '16:30', '2024-09-05', '2025-01-23', 'tp', 'confirme'),
       (7, 12, 10, 4, '13:30', '16:30', '2024-09-05', '2025-01-23', 'tp', 'confirme');

-- Vendredi (5)
INSERT INTO creneaux_horaires (professeur_id, matiere_id, salle_id, jour_semaine, heure_debut, heure_fin, date_debut,
                               date_fin, type_seance, statut)
VALUES (8, 15, 9, 5, '08:00', '11:00', '2024-09-06', '2025-01-24', 'tp', 'confirme'),
       (9, 18, 10, 5, '08:00', '11:00', '2024-09-06', '2025-01-24', 'tp', 'confirme'),
       (3, 3, 8, 5, '13:30', '16:30', '2024-09-06', '2025-01-24', 'tp', 'confirme');


-- =============================================
-- REQUETES COMPLEXES AVEC JOINTURES ET AGREGATIONS
-- =============================================

-- 1. REQUETE : Emploi du temps complet d'un professeur
SELECT p.nom || ' ' || p.prenom AS professeur,
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
       s.numero                 AS salle,
       b.nom                    AS batiment,
       ch.type_seance,
       ch.statut
FROM creneaux_horaires ch
         JOIN professeurs p ON ch.professeur_id = p.id
         JOIN matieres m ON ch.matiere_id = m.id
         JOIN salles s ON ch.salle_id = s.id
         JOIN batiments b ON s.batiment_id = b.id
WHERE p.code = 'PAM'
  AND ch.statut IN ('planifie', 'confirme')
ORDER BY ch.jour_semaine, ch.heure_debut;

-- 2. REQUETE : Nombre d'heures par professeur et par semaine
SELECT p.code,
       p.nom || ' ' || p.prenom                                                  AS professeur,
       pr.nom                                                                    AS programme,
       COUNT(ch.id)                                                              AS nombre_cours_semaine,
       ROUND(SUM(EXTRACT(EPOCH FROM (ch.heure_fin - ch.heure_debut)) / 3600), 1) AS heures_total_semaine
FROM professeurs p
         JOIN programmes pr ON p.programmes_id = pr.id
         JOIN creneaux_horaires ch ON p.id = ch.professeur_id
WHERE ch.statut IN ('planifie', 'confirme')
GROUP BY p.id, p.code, p.nom, p.prenom, pr.nom
ORDER BY heures_total_semaine DESC;

-- 3. REQUETE : Salles les plus utilisées
SELECT b.nom                            AS batiment,
       s.numero                         AS salle,
       s.type_salle,
       s.capacite,
       COUNT(ch.id)                     AS nombre_creneaux,
       COUNT(DISTINCT ch.professeur_id) AS nombre_professeurs,
       COUNT(DISTINCT ch.matiere_id)    AS nombre_matieres
FROM salles s
         JOIN batiments b ON s.batiment_id = b.id
         LEFT JOIN creneaux_horaires ch ON s.id = ch.salle_id
    AND ch.statut IN ('planifie', 'confirme')
GROUP BY b.nom, s.id, s.numero, s.type_salle, s.capacite
ORDER BY nombre_creneaux DESC;

-- 5. REQUETE : Statistiques par programme
SELECT pr.nom                    AS programme,
       COUNT(DISTINCT p.id)      AS nombre_professeurs,
       COUNT(DISTINCT m.id)      AS nombre_matieres,
       COUNT(ch.id)              AS nombre_creneaux,
       ROUND(AVG(s.capacite), 0) AS capacite_moyenne_salle,
       SUM(ap.heures_attribuees) AS total_heures_attribuees
FROM programmes pr
         LEFT JOIN professeurs p ON pr.id = p.programmes_id
         LEFT JOIN matieres m ON pr.id = m.programmes_id
         LEFT JOIN creneaux_horaires ch ON p.id = ch.professeur_id
    AND ch.statut IN ('planifie', 'confirme')
         LEFT JOIN salles s ON ch.salle_id = s.id
         LEFT JOIN affectations_professeurs ap ON p.id = ap.professeur_id
    AND ap.annee_academique = '2024-2025'
GROUP BY pr.id, pr.nom
ORDER BY nombre_creneaux DESC;

-- 6. REQUETE : Disponibilité des salles à un moment donné
SELECT b.nom    AS batiment,
       s.numero AS salle,
       s.type_salle,
       s.capacite,
       s.statut,
       CASE
           WHEN EXISTS (SELECT 1
                        FROM creneaux_horaires ch
                        WHERE ch.salle_id = s.id
                          AND ch.jour_semaine = EXTRACT(ISODOW FROM CURRENT_DATE)
                          AND ch.heure_debut <= '10:00'::TIME
                          AND ch.heure_fin >= '12:00'::TIME
                          AND ch.date_debut <= CURRENT_DATE
                          AND ch.date_fin >= CURRENT_DATE
                          AND ch.statut IN ('planifie', 'confirme')) THEN 'Occupée'
           ELSE 'Disponible'
           END  AS statut_horaire
FROM salles s
         JOIN batiments b ON s.batiment_id = b.id
WHERE s.statut = 'disponible'
ORDER BY b.nom, s.etage, s.numero;

-- =============================================
-- OPÉRATIONS DE MISE À JOUR
-- =============================================

-- 2. MISE À JOUR : Reporter un créneau horaire
UPDATE creneaux_horaires
SET statut     = 'reporte',
    notes      = CONCAT(COALESCE(notes, ''), ' Reporté pour cause de maintenance salle. '),
    updated_at = CURRENT_TIMESTAMP
WHERE salle_id IN (SELECT id
                   FROM salles
                   WHERE numero = 'A202'
                     AND statut = 'maintenance')
  AND date_debut >= CURRENT_DATE
RETURNING id, professeur_id, matiere_id, date_debut, statut;

-- =============================================
-- OPÉRATIONS DE SUPPRESSION
-- =============================================

-- 1. SUPPRESSION : Supprimer les créneaux annulés de plus d'un mois
DELETE
FROM creneaux_horaires
WHERE statut = 'annule'
  AND updated_at < CURRENT_DATE - INTERVAL '30 days'
RETURNING id, professeur_id, matiere_id, date_debut;

-- 1. Vérifier les créneaux sans professeur valide
SELECT ch.id                    AS creneau_id,
       ch.date_debut,
       ch.heure_debut,
       m.nom                    AS matiere,
       p.nom || ' ' || p.prenom AS professeur,
       p.actif
FROM creneaux_horaires ch
         JOIN professeurs p ON ch.professeur_id = p.id
         JOIN matieres m ON ch.matiere_id = m.id
WHERE p.actif = false
  AND ch.statut IN ('planifie', 'confirme')
  AND ch.date_debut >= CURRENT_DATE;

-- 3. Vérifier les conflits d'horaire malgré les contraintes
SELECT 'CONFLIT' AS type,
       p1.nom    AS professeur1,
       p2.nom    AS professeur2,
       ch1.heure_debut,
       ch1.heure_fin,
       ch1.jour_semaine
FROM creneaux_horaires ch1
         JOIN creneaux_horaires ch2 ON
    ch1.professeur_id = ch2.professeur_id
        AND ch1.id != ch2.id
        AND ch1.jour_semaine = ch2.jour_semaine
        AND (ch1.heure_debut, ch1.heure_fin) OVERLAPS (ch2.heure_debut, ch2.heure_fin)
        AND ch1.date_debut <= ch2.date_fin
        AND ch1.date_fin >= ch2.date_debut
         JOIN professeurs p1 ON ch1.professeur_id = p1.id
         JOIN professeurs p2 ON ch2.professeur_id = p2.id
WHERE ch1.statut IN ('planifie', 'confirme')
  AND ch2.statut IN ('planifie', 'confirme')
LIMIT 5;

