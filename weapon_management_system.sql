-- ============================================================================
-- DATABASE MANAGEMENT SYSTEMS (DBMS) MINI-PROJECT
-- PROJECT TITLE : Weapon Management System (WMS)
-- RDBMS ENGINE  : MySQL 8.0+ / MariaDB 10.5+
-- ENVIRONMENT   : MySQL Workbench / MySQL CLI
-- OBJECTIVE     : Secure inventory tracking, accountability, custody transfers,
--                 maintenance scheduling, and role-based access control.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- STEP 1: DATABASE INITIALIZATION
-- ----------------------------------------------------------------------------
--DROP DATABASE IF EXISTS weapon_management_db;
CREATE DATABASE weapon_management_db
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE weapon_management_db;

-- ----------------------------------------------------------------------------
-- STEP 2: TABLE DEFINITIONS (DDL) WITH CONSTRAINTS & RELATIONSHIPS
-- ----------------------------------------------------------------------------

-- Table 1: Admin / System Users
-- Manages administrative personnel authorized to oversee and approve armory operations
CREATE TABLE Admin (
    admin_id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(100) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    role ENUM('SuperAdmin', 'Armory Officer', 'Duty Officer', 'Maintenance Tech') NOT NULL DEFAULT 'Duty Officer',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Table 2: Category
-- Classifies weaponry into standard tactical/firearm classifications
CREATE TABLE Category (
    category_id INT AUTO_INCREMENT PRIMARY KEY,
    category_name VARCHAR(50) NOT NULL UNIQUE,
    description VARCHAR(255)
) ENGINE=InnoDB;

-- Table 3: Storage
-- Designates physical secure vaults, armory bays, and secured lockers
CREATE TABLE Storage (
    storage_id INT AUTO_INCREMENT PRIMARY KEY,
    storage_location VARCHAR(100) NOT NULL UNIQUE,
    capacity INT NOT NULL CHECK (capacity > 0),
    security_level ENUM('Level 1 - General', 'Level 2 - High Security', 'Level 3 - Restricted Vault') NOT NULL DEFAULT 'Level 2 - High Security'
) ENGINE=InnoDB;

-- Table 4: Personnel
-- Authorized service members, officers, or tactical personnel who can be allocated weapons
CREATE TABLE Personnel (
    personnel_id INT AUTO_INCREMENT PRIMARY KEY,
    badge_number VARCHAR(30) NOT NULL UNIQUE,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    rank_designation VARCHAR(50) NOT NULL,
    department VARCHAR(80) NOT NULL,
    contact_number VARCHAR(20) NOT NULL,
    clearance_level ENUM('Confidential', 'Secret', 'Top Secret') NOT NULL DEFAULT 'Secret',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Table 5: Weapon
-- Core asset table tracking individual serial-numbered firearms and tactical gear
CREATE TABLE Weapon (
    weapon_id INT AUTO_INCREMENT PRIMARY KEY,
    weapon_name VARCHAR(100) NOT NULL,
    category_id INT NOT NULL,
    storage_id INT NOT NULL,
    serial_number VARCHAR(50) NOT NULL UNIQUE,
    caliber VARCHAR(30) NOT NULL,
    manufacturer VARCHAR(80) NOT NULL,
    condition_status ENUM('Serviceable', 'Needs Repair', 'Critical Inspection', 'Unserviceable') NOT NULL DEFAULT 'Serviceable',
    status ENUM('Available', 'Issued', 'Under Maintenance', 'Decommissioned') NOT NULL DEFAULT 'Available',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_weapon_category FOREIGN KEY (category_id)
        REFERENCES Category(category_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,
    CONSTRAINT fk_weapon_storage FOREIGN KEY (storage_id)
        REFERENCES Storage(storage_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
) ENGINE=InnoDB;

-- Table 6: Weapon_Allocation
-- Tracks issuance, chain of custody, expected return, and return verification
CREATE TABLE Weapon_Allocation (
    allocation_id INT AUTO_INCREMENT PRIMARY KEY,
    weapon_id INT NOT NULL,
    personnel_id INT NOT NULL,
    admin_id INT NOT NULL,
    issue_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expected_return_date DATETIME NOT NULL,
    actual_return_date DATETIME DEFAULT NULL,
    purpose VARCHAR(255) NOT NULL,
    approval_status ENUM('Pending', 'Approved', 'Returned', 'Overdue', 'Rejected') NOT NULL DEFAULT 'Approved',
    remarks VARCHAR(255) DEFAULT NULL,
    CONSTRAINT fk_alloc_weapon FOREIGN KEY (weapon_id)
        REFERENCES Weapon(weapon_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,
    CONSTRAINT fk_alloc_personnel FOREIGN KEY (personnel_id)
        REFERENCES Personnel(personnel_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,
    CONSTRAINT fk_alloc_admin FOREIGN KEY (admin_id)
        REFERENCES Admin(admin_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,
    CONSTRAINT chk_return_date CHECK (expected_return_date >= issue_date)
) ENGINE=InnoDB;

-- Table 7: Maintenance
-- Service logs, regular inspections, test-fires, and repair audits
CREATE TABLE Maintenance (
    maintenance_id INT AUTO_INCREMENT PRIMARY KEY,
    weapon_id INT NOT NULL,
    maintenance_date DATE NOT NULL,
    condition_assessed ENUM('Serviceable', 'Needs Repair', 'Critical Inspection', 'Unserviceable') NOT NULL,
    technician_name VARCHAR(100) NOT NULL,
    remarks TEXT NOT NULL,
    cost DECIMAL(10, 2) NOT NULL DEFAULT 0.00 CHECK (cost >= 0.00),
    next_service_due DATE DEFAULT NULL,
    CONSTRAINT fk_maint_weapon FOREIGN KEY (weapon_id)
        REFERENCES Weapon(weapon_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
) ENGINE=InnoDB;

-- Table 8: Allocation_Audit_Log (Advanced DBMS Feature: Automated Audit Logging)
CREATE TABLE Allocation_Audit_Log (
    log_id INT AUTO_INCREMENT PRIMARY KEY,
    allocation_id INT NOT NULL,
    weapon_id INT NOT NULL,
    personnel_id INT NOT NULL,
    action_type ENUM('ISSUE', 'RETURN', 'OVERDUE_FLAG') NOT NULL,
    action_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    notes VARCHAR(255)
) ENGINE=InnoDB;


-- ----------------------------------------------------------------------------
-- STEP 3: INDEXES FOR PERFORMANCE OPTIMIZATION
-- ----------------------------------------------------------------------------
CREATE INDEX idx_weapon_serial ON Weapon(serial_number);
CREATE INDEX idx_weapon_status ON Weapon(status);
CREATE INDEX idx_weapon_category ON Weapon(category_id);
CREATE INDEX idx_allocation_dates ON Weapon_Allocation(issue_date, expected_return_date, actual_return_date);
CREATE INDEX idx_personnel_badge ON Personnel(badge_number);
CREATE INDEX idx_maintenance_date ON Maintenance(maintenance_date);


-- ----------------------------------------------------------------------------
-- STEP 4: TRIGGERS FOR DATA INTEGRITY AND AUTOMATION
-- ----------------------------------------------------------------------------

DELIMITER $$

-- Trigger 1: Prevent issuing a weapon if it is NOT in 'Available' status
CREATE TRIGGER trg_before_weapon_allocation_insert
BEFORE INSERT ON Weapon_Allocation
FOR EACH ROW
BEGIN
    DECLARE current_weapon_status VARCHAR(30);

    SELECT status INTO current_weapon_status
    FROM Weapon
    WHERE weapon_id = NEW.weapon_id;

    IF current_weapon_status != 'Available' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: Cannot allocate weapon. Asset is not currently Available (Already Issued, Under Maintenance, or Decommissioned).';
    END IF;
END$$

-- Trigger 2: Automatically update Weapon status to 'Issued' upon new allocation
CREATE TRIGGER trg_after_weapon_allocation_insert
AFTER INSERT ON Weapon_Allocation
FOR EACH ROW
BEGIN
    UPDATE Weapon
    SET status = 'Issued'
    WHERE weapon_id = NEW.weapon_id;

    -- Record in audit log
    INSERT INTO Allocation_Audit_Log (allocation_id, weapon_id, personnel_id, action_type, notes)
    VALUES (NEW.allocation_id, NEW.weapon_id, NEW.personnel_id, 'ISSUE', CONCAT('Weapon issued for purpose: ', NEW.purpose));
END$$

-- Trigger 3: Automatically update Weapon status back to 'Available' when returned
CREATE TRIGGER trg_after_weapon_allocation_update
AFTER UPDATE ON Weapon_Allocation
FOR EACH ROW
BEGIN
    -- If weapon was returned (actual_return_date populated and previously null)
    IF OLD.actual_return_date IS NULL AND NEW.actual_return_date IS NOT NULL THEN
        UPDATE Weapon
        SET status = 'Available'
        WHERE weapon_id = NEW.weapon_id;

        -- Record return in audit log
        INSERT INTO Allocation_Audit_Log (allocation_id, weapon_id, personnel_id, action_type, notes)
        VALUES (NEW.allocation_id, NEW.weapon_id, NEW.personnel_id, 'RETURN', 'Weapon returned and verified by armory officer.');
    END IF;
END$$

-- Trigger 4: Update weapon condition & status after maintenance inspection
CREATE TRIGGER trg_after_maintenance_insert
AFTER INSERT ON Maintenance
FOR EACH ROW
BEGIN
    UPDATE Weapon
    SET condition_status = NEW.condition_assessed,
        status = CASE
            WHEN NEW.condition_assessed = 'Unserviceable' THEN 'Decommissioned'
            WHEN NEW.condition_assessed = 'Critical Inspection' THEN 'Under Maintenance'
            ELSE 'Available'
        END
    WHERE weapon_id = NEW.weapon_id;
END$$

DELIMITER ;


-- ----------------------------------------------------------------------------
-- STEP 5: SAMPLE DATA INSERTION (DML)
-- ----------------------------------------------------------------------------

-- Insert Admins
INSERT INTO Admin (username, password_hash, full_name, email, role) VALUES
('adm_vance', SHA2('VancePass@2026', 256), 'Maj. Marcus Vance', 'm.vance@armory.gov', 'SuperAdmin'),
('adm_cross', SHA2('CrossPass@2026', 256), 'Capt. Sarah Cross', 's.cross@armory.gov', 'Armory Officer'),
('adm_reyes', SHA2('ReyesPass@2026', 256), 'Lt. Daniel Reyes', 'd.reyes@armory.gov', 'Duty Officer'),
('adm_chen',  SHA2('ChenPass@2026', 256),  'Tech. Kevin Chen', 'k.chen@armory.gov', 'Maintenance Tech');

-- Insert Categories
INSERT INTO Category (category_name, description) VALUES
('Sidearms / Pistols', 'Semi-automatic tactical handguns for close quarter & sidearm carry'),
('Assault Rifles', 'Selective-fire military/tactical intermediate caliber rifles'),
('Sniper Systems', 'High-precision long-range rifles with magnified optics'),
('Shotguns', 'Tactical 12-gauge breaching and perimeter defense shotguns'),
('Submachine Guns', 'Compact automatic carbines and pistol-caliber weapon systems'),
('Non-Lethal Gear', 'Tasers, bean-bag projectors, and riot deterrent hardware');

-- Insert Storage Locations
INSERT INTO Storage (storage_location, capacity, security_level) VALUES
('Vault Alpha - Rack 01', 30, 'Level 3 - Restricted Vault'),
('Vault Alpha - Rack 02', 30, 'Level 3 - Restricted Vault'),
('Armory Bay Central - Section A', 50, 'Level 2 - High Security'),
('Armory Bay Central - Section B', 50, 'Level 2 - High Security'),
('Quick-Response Locker Unit 4', 15, 'Level 1 - General');

-- Insert Personnel
INSERT INTO Personnel (badge_number, first_name, last_name, rank_designation, department, contact_number, clearance_level) VALUES
('BADGE-101', 'Alexander', 'Pierce', 'Commander', 'Special Tactics Unit', '+1-555-0191', 'Top Secret'),
('BADGE-102', 'Elena', 'Rostova', 'Lieutenant', 'Tactical Response Division', '+1-555-0192', 'Secret'),
('BADGE-103', 'David', 'Miller', 'Detective Sergeant', 'Major Crimes Taskforce', '+1-555-0193', 'Secret'),
('BADGE-104', 'James', 'O''Connor', 'Special Agent', 'VIP Protection Detail', '+1-555-0194', 'Top Secret'),
('BADGE-105', 'Amina', 'Khoury', 'Patrol Officer', 'Metropolitan Patrol Unit', '+1-555-0195', 'Confidential'),
('BADGE-106', 'Lucas', 'Silva', 'Senior Sergeant', 'Border & Perimeter Security', '+1-555-0196', 'Secret'),
('BADGE-107', 'Rachel', 'Adams', 'Tactical Marksman', 'Special Tactics Unit', '+1-555-0197', 'Top Secret'),
('BADGE-108', 'Nathan', 'Drake', 'Inspector', 'Internal Security Division', '+1-555-0198', 'Secret');

-- Insert Weapons (All initially Available)
INSERT INTO Weapon (weapon_name, category_id, storage_id, serial_number, caliber, manufacturer, condition_status, status) VALUES
('Glock 19 Gen5',          1, 5, 'GLK-19-98214', '9x19mm Parabellum', 'Glock Ges.m.b.H.', 'Serviceable', 'Available'),
('Sig Sauer P320-M17',     1, 5, 'SIG-32-44102', '9x19mm Parabellum', 'Sig Sauer Inc.',   'Serviceable', 'Available'),
('Beretta M9A3',           1, 3, 'BER-M9-77190', '9x19mm Parabellum', 'Beretta Arms',     'Serviceable', 'Available'),
('Colt M4A1 Carbine',      2, 1, 'CLT-M4-10023', '5.56x45mm NATO',    'Colt Defense',      'Serviceable', 'Available'),
('FN SCAR-L Mk16',         2, 1, 'FNS-16-65412', '5.56x45mm NATO',    'FN Herstal',        'Serviceable', 'Available'),
('HK416 A5',               2, 1, 'HK4-16-90871', '5.56x45mm NATO',    'Heckler & Koch',    'Serviceable', 'Available'),
('Accuracy Int. AX308',    3, 2, 'AIX-08-33219', '.308 Winchester',   'Accuracy Int.',     'Serviceable', 'Available'),
('Barrett MRAD Mk22',      3, 2, 'BAR-22-12098', '.338 Lapua Mag',    'Barrett Firearms',  'Serviceable', 'Available'),
('Benelli M4 Super 90',    4, 4, 'BEN-M4-55120', '12 Gauge 3-inch',   'Benelli Armi',      'Serviceable', 'Available'),
('Remington 870 Tactical', 4, 4, 'REM-87-78921', '12 Gauge 2.75-in',  'Remington Arms',    'Serviceable', 'Available'),
('HK MP5A3 Submachine Gun',5, 3, 'HK5-MP-88314', '9x19mm Parabellum', 'Heckler & Koch',    'Serviceable', 'Available'),
('SIG MPX Copperhead',     5, 3, 'SIG-MP-99411', '9x19mm Parabellum', 'Sig Sauer Inc.',   'Serviceable', 'Available'),
('Axon Taser 7',           6, 5, 'TSR-07-22310', 'High-Voltage Pulse', 'Axon Enterprise',  'Serviceable', 'Available'),
('Mossberg 590 Less-Lethal', 6, 4,'MOS-59-66120', '12 Ga Bean Bag',    'O.F. Mossberg',     'Serviceable', 'Available'),
('Walther PPQ M2',         1, 5, 'WLT-PQ-51009', '9x19mm Parabellum', 'Carl Walther',      'Needs Repair', 'Available');

-- Insert Allocations (Triggers will automatically set weapon status to 'Issued')
INSERT INTO Weapon_Allocation (weapon_id, personnel_id, admin_id, issue_date, expected_return_date, actual_return_date, purpose, approval_status, remarks) VALUES
-- Allocation 1: Already returned on time
(1, 1, 2, '2026-10-10 08:00:00', '2026-10-10 18:00:00', '2026-10-10 17:45:00', 'VIP Escort Mission', 'Returned', 'Returned in clean condition'),
-- Allocation 2: Currently active and valid (Within expected return)
(4, 1, 2, '2026-10-25 07:30:00', '2026-10-28 20:00:00', NULL, 'Rapid Deployment Drill', 'Approved', 'Special tactical attachment authorized'),
-- Allocation 3: OVERDUE return! (Expected return passed, not returned yet)
(7, 7, 2, '2026-10-15 09:00:00', '2026-10-20 18:00:00', NULL, 'Perimeter Surveillance Duty', 'Overdue', 'Officer contacted regarding overdue status'),
-- Allocation 4: Currently active sidearm allocation
(2, 2, 3, '2026-10-26 08:00:00', '2026-10-28 18:00:00', NULL, 'Downtown Patrol Shift', 'Approved', 'Standard dual magazine allotment'),
-- Allocation 5: Overdue non-lethal equipment
(13, 5, 3, '2026-10-18 06:00:00', '2026-10-22 18:00:00', NULL, 'Crowd Management Operation', 'Overdue', 'Reminder issued to supervisor'),
-- Allocation 6: Returned shotgun
(9, 6, 2, '2026-10-12 10:00:00', '2026-10-14 18:00:00', '2026-10-14 16:30:00', 'Border Outpost Defense', 'Returned', 'Routine cleaning completed');

-- Insert Maintenance Records
INSERT INTO Maintenance (weapon_id, maintenance_date, condition_assessed, technician_name, remarks, cost, next_service_due) VALUES
(1, '2026-08-15', 'Serviceable', 'Tech. Kevin Chen', 'Field stripped, ultrasonically cleaned, firing pin inspected.', 45.00, '2027-02-15'),
(4, '2026-09-01', 'Serviceable', 'Tech. Kevin Chen', 'Bore rifling verified, gas block tuned, 100-round test fire passed.', 120.00, '2027-03-01'),
(7, '2026-07-20', 'Serviceable', 'Armorer Greg Hayes', 'Optical scope zeroed at 300m, bolt headspace checked.', 250.00, '2027-01-20'),
(15, '2026-10-05', 'Needs Repair', 'Tech. Kevin Chen', 'Extractor tension weak; failure to extract during test cycles. Awaiting replacement parts.', 85.00, '2026-11-05'),
(10, '2026-09-12', 'Serviceable', 'Tech. Kevin Chen', 'Action spring replaced, magazine follower lubricated.', 60.00, '2027-03-12');


-- ----------------------------------------------------------------------------
-- STEP 6: VIEWS CREATION FOR REPORTING & ABSTRACTION
-- ----------------------------------------------------------------------------

-- View 1: Current Active Weapon Allocations with Custodian Details
CREATE OR REPLACE VIEW vw_active_allocations AS
SELECT 
    wa.allocation_id,
    w.weapon_id,
    w.serial_number,
    w.weapon_name,
    c.category_name,
    CONCAT(p.first_name, ' ', p.last_name) AS issued_to_officer,
    p.badge_number,
    p.rank_designation,
    p.department,
    wa.issue_date,
    wa.expected_return_date,
    wa.purpose,
    wa.approval_status,
    adm.full_name AS authorized_by_admin
FROM Weapon_Allocation wa
JOIN Weapon w ON wa.weapon_id = w.weapon_id
JOIN Category c ON w.category_id = c.category_id
JOIN Personnel p ON wa.personnel_id = p.personnel_id
JOIN Admin adm ON wa.admin_id = adm.admin_id
WHERE wa.actual_return_date IS NULL;

-- View 2: Overdue Weapon Returns Watchlist
CREATE OR REPLACE VIEW vw_overdue_allocations AS
SELECT 
    wa.allocation_id,
    w.serial_number,
    w.weapon_name,
    CONCAT(p.first_name, ' ', p.last_name) AS personnel_name,
    p.badge_number,
    p.contact_number,
    wa.issue_date,
    wa.expected_return_date,
    DATEDIFF(CURRENT_TIMESTAMP, wa.expected_return_date) AS days_overdue,
    wa.purpose
FROM Weapon_Allocation wa
JOIN Weapon w ON wa.weapon_id = w.weapon_id
JOIN Personnel p ON wa.personnel_id = p.personnel_id
WHERE wa.actual_return_date IS NULL 
  AND wa.expected_return_date < CURRENT_TIMESTAMP;

-- View 3: Complete Armory Inventory Status
CREATE OR REPLACE VIEW vw_weapon_inventory_summary AS
SELECT 
    w.weapon_id,
    w.serial_number,
    w.weapon_name,
    c.category_name,
    s.storage_location,
    s.security_level,
    w.condition_status,
    w.status AS custody_status,
    w.caliber,
    w.manufacturer
FROM Weapon w
JOIN Category c ON w.category_id = c.category_id
JOIN Storage s ON w.storage_id = s.storage_id;


-- ----------------------------------------------------------------------------
-- STEP 7: STORED PROCEDURES (BUSINESS LOGIC WITH TRANSACTIONS)
-- ----------------------------------------------------------------------------

DELIMITER $$

-- Stored Procedure to safely issue a weapon within an ACID transaction
CREATE PROCEDURE sp_issue_weapon(
    IN p_weapon_id INT,
    IN p_personnel_id INT,
    IN p_admin_id INT,
    IN p_expected_return DATETIME,
    IN p_purpose VARCHAR(255),
    OUT p_allocation_id INT,
    OUT p_result_message VARCHAR(255)
)
proc_block: BEGIN
    DECLARE v_current_status VARCHAR(30);
    DECLARE v_officer_exists INT;

    -- Error Handler for unexpected SQL exceptions
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_result_message = 'ERROR: Database transaction failed during weapon issuance.';
        SET p_allocation_id = NULL;
    END;

    START TRANSACTION;

    -- Verify Officer exists
    SELECT COUNT(*) INTO v_officer_exists FROM Personnel WHERE personnel_id = p_personnel_id;
    IF v_officer_exists = 0 THEN
        SET p_result_message = 'ERROR: Personnel record not found.';
        ROLLBACK;
        LEAVE proc_block;
    END IF;

    -- Check Weapon Availability
    SELECT status INTO v_current_status FROM Weapon WHERE weapon_id = p_weapon_id FOR UPDATE;
    IF v_current_status IS NULL THEN
        SET p_result_message = 'ERROR: Weapon ID does not exist.';
        ROLLBACK;
        LEAVE proc_block;
    ELSEIF v_current_status != 'Available' THEN
        SET p_result_message = CONCAT('ERROR: Weapon is currently not available. Current status: ', v_current_status);
        ROLLBACK;
        LEAVE proc_block;
    END IF;

    -- Insert Allocation Record (Triggers will automate weapon status to 'Issued' & log audit)
    INSERT INTO Weapon_Allocation (
        weapon_id, personnel_id, admin_id, issue_date, expected_return_date, actual_return_date, purpose, approval_status
    ) VALUES (
        p_weapon_id, p_personnel_id, p_admin_id, CURRENT_TIMESTAMP, p_expected_return, NULL, p_purpose, 'Approved'
    );

    SET p_allocation_id = LAST_INSERT_ID();
    COMMIT;
    SET p_result_message = CONCAT('SUCCESS: Weapon successfully issued under Allocation ID: ', p_allocation_id);
END$$

-- Stored Procedure to process weapon return safely
CREATE PROCEDURE sp_return_weapon(
    IN p_allocation_id INT,
    IN p_return_remarks VARCHAR(255),
    OUT p_result_message VARCHAR(255)
)
proc_block: BEGIN
    DECLARE v_actual_date DATETIME;
    DECLARE v_weapon_id INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_result_message = 'ERROR: Database transaction failed during weapon return.';
    END;

    START TRANSACTION;

    SELECT actual_return_date, weapon_id INTO v_actual_date, v_weapon_id
    FROM Weapon_Allocation
    WHERE allocation_id = p_allocation_id FOR UPDATE;

    IF v_weapon_id IS NULL THEN
        SET p_result_message = 'ERROR: Allocation ID does not exist.';
        ROLLBACK;
        LEAVE proc_block;
    ELSEIF v_actual_date IS NOT NULL THEN
        SET p_result_message = 'ERROR: This weapon allocation was already marked returned.';
        ROLLBACK;
        LEAVE proc_block;
    END IF;

    -- Update return date and status (Triggers will update Weapon.status to 'Available' & log audit)
    UPDATE Weapon_Allocation
    SET actual_return_date = CURRENT_TIMESTAMP,
        approval_status = 'Returned',
        remarks = p_return_remarks
    WHERE allocation_id = p_allocation_id;

    COMMIT;
    SET p_result_message = CONCAT('SUCCESS: Weapon return processed successfully for Allocation ID: ', p_allocation_id);
END$$

DELIMITER ;


-- ----------------------------------------------------------------------------
-- STEP 8: COMPREHENSIVE SQL QUERIES (DQL, AGGREGATIONS, JOINS, SUBQUERIES)
-- ----------------------------------------------------------------------------

-- Query 1: Retrieve all weapons with their category names and storage locations
SELECT 
    w.weapon_id,
    w.serial_number,
    w.weapon_name,
    c.category_name,
    s.storage_location,
    w.condition_status,
    w.status AS availability_status
FROM Weapon w
INNER JOIN Category c ON w.category_id = c.category_id
INNER JOIN Storage s ON w.storage_id = s.storage_id
ORDER BY c.category_name, w.weapon_name;

-- Query 2: Search weapons by specific weapon ID or category name
SELECT 
    w.weapon_id,
    w.serial_number,
    w.weapon_name,
    w.caliber,
    c.category_name,
    w.status
FROM Weapon w
JOIN Category c ON w.category_id = c.category_id
WHERE w.weapon_id = 4 OR c.category_name LIKE '%Rifle%';

-- Query 3: Display authorized personnel and their active assigned weapons (Multi-table JOIN)
SELECT 
    p.badge_number,
    CONCAT(p.first_name, ' ', p.last_name) AS officer_name,
    p.rank_designation,
    p.department,
    w.weapon_name,
    w.serial_number,
    wa.issue_date,
    wa.expected_return_date,
    wa.purpose
FROM Personnel p
INNER JOIN Weapon_Allocation wa ON p.personnel_id = wa.personnel_id
INNER JOIN Weapon w ON wa.weapon_id = w.weapon_id
WHERE wa.actual_return_date IS NULL
ORDER BY wa.issue_date DESC;

-- Query 4: Identify Overdue weapon returns (Critical security check)
SELECT 
    wa.allocation_id,
    w.serial_number,
    w.weapon_name,
    CONCAT(p.first_name, ' ', p.last_name) AS custodian,
    p.contact_number,
    wa.issue_date,
    wa.expected_return_date,
    TIMESTAMPDIFF(HOUR, wa.expected_return_date, CURRENT_TIMESTAMP) AS overdue_hours
FROM Weapon_Allocation wa
JOIN Weapon w ON wa.weapon_id = w.weapon_id
JOIN Personnel p ON wa.personnel_id = p.personnel_id
WHERE wa.actual_return_date IS NULL 
  AND wa.expected_return_date < CURRENT_TIMESTAMP;

-- Query 5: Generate Comprehensive Maintenance Report
SELECT 
    m.maintenance_id,
    w.serial_number,
    w.weapon_name,
    c.category_name,
    m.maintenance_date,
    m.condition_assessed,
    m.technician_name,
    m.cost,
    m.remarks
FROM Maintenance m
JOIN Weapon w ON m.weapon_id = w.weapon_id
JOIN Category c ON w.category_id = c.category_id
ORDER BY m.maintenance_date DESC;

-- Query 6: Aggregate Functions - Weapon count and distribution by category
SELECT 
    c.category_name,
    COUNT(w.weapon_id) AS total_weapons,
    SUM(CASE WHEN w.status = 'Available' THEN 1 ELSE 0 END) AS available_count,
    SUM(CASE WHEN w.status = 'Issued' THEN 1 ELSE 0 END) AS issued_count,
    SUM(CASE WHEN w.status = 'Under Maintenance' THEN 1 ELSE 0 END) AS maintenance_count
FROM Category c
LEFT JOIN Weapon w ON c.category_id = w.category_id
GROUP BY c.category_id, c.category_name
ORDER BY total_weapons DESC;

-- Query 7: Storage Utilization Analysis (Storage Capacity vs Current Weapons Housed)
SELECT 
    s.storage_id,
    s.storage_location,
    s.capacity,
    COUNT(w.weapon_id) AS current_weapons_stored,
    (s.capacity - COUNT(w.weapon_id)) AS available_slots,
    ROUND((COUNT(w.weapon_id) / s.capacity) * 100, 2) AS utilization_percentage
FROM Storage s
LEFT JOIN Weapon w ON s.storage_id = w.storage_id
GROUP BY s.storage_id, s.storage_location, s.capacity
HAVING current_weapons_stored > 0
ORDER BY utilization_percentage DESC;

-- Query 8: Subquery with IN - Personnel who have active weapon allocations
SELECT 
    personnel_id,
    badge_number,
    CONCAT(first_name, ' ', last_name) AS full_name,
    rank_designation,
    department
FROM Personnel
WHERE personnel_id IN (
    SELECT DISTINCT personnel_id 
    FROM Weapon_Allocation 
    WHERE actual_return_date IS NULL
);

-- Query 9: Subquery with NOT EXISTS - Weapons that have NEVER undergone maintenance
SELECT 
    w.weapon_id,
    w.serial_number,
    w.weapon_name,
    c.category_name,
    w.condition_status
FROM Weapon w
JOIN Category c ON w.category_id = c.category_id
WHERE NOT EXISTS (
    SELECT 1 
    FROM Maintenance m 
    WHERE m.weapon_id = w.weapon_id
);

-- Query 10: Scalar Subquery - Maintenance tasks exceeding the average maintenance cost
SELECT 
    m.maintenance_id,
    w.weapon_name,
    w.serial_number,
    m.maintenance_date,
    m.technician_name,
    m.cost
FROM Maintenance m
JOIN Weapon w ON m.weapon_id = w.weapon_id
WHERE m.cost > (
    SELECT AVG(cost) FROM Maintenance
)
ORDER BY m.cost DESC;


-- ----------------------------------------------------------------------------
-- STEP 9: TRANSACTION MANAGEMENT (ACID DEMONSTRATION WITH COMMIT & ROLLBACK)
-- ----------------------------------------------------------------------------

-- Transaction Demo 1: Successful allocation using Stored Procedure (ACID: Atomicity & Consistency)
CALL sp_issue_weapon(
    3,                     -- Weapon: Beretta M9A3 (Available)
    3,                     -- Officer: Det. Sgt. David Miller
    2,                     -- Admin: Sarah Cross
    DATE_ADD(CURRENT_TIMESTAMP, INTERVAL 2 DAY),
    'Tactical Undercover Operation',
    @new_alloc_id,
    @exec_msg
);
SELECT @new_alloc_id AS generated_allocation_id, @exec_msg AS execution_result;

-- Transaction Demo 2: Failed allocation due to business rule validation (Weapon already issued)
-- Demonstrates automatic ROLLBACK when trying to issue weapon 4 (Colt M4A1, already 'Issued')
CALL sp_issue_weapon(
    4,                     -- Weapon 4 is already Issued
    4,                     -- Special Agent James O'Connor
    2,                     -- Admin: Sarah Cross
    DATE_ADD(CURRENT_TIMESTAMP, INTERVAL 1 DAY),
    'Counter-Terror Patrol',
    @failed_alloc_id,
    @failed_msg
);
SELECT @failed_alloc_id AS generated_allocation_id, @failed_msg AS execution_result;

-- Transaction Demo 3: Explicit Manual Transaction with ROLLBACK Demonstration
START TRANSACTION;
    -- Step A: Insert a speculative maintenance record
    INSERT INTO Maintenance (weapon_id, maintenance_date, condition_assessed, technician_name, remarks, cost)
    VALUES (6, CURRENT_DATE(), 'Critical Inspection', 'Tech. Kevin Chen', 'Barrel thermal fracture suspected', 500.00);

    -- Step B: Inspect state within transaction
    SELECT weapon_id, condition_assessed, cost FROM Maintenance WHERE weapon_id = 6;

    -- Step C: Encounter an error or cancellation reason -> Roll back entire operation
ROLLBACK;

-- Verify rollback: Confirm no record was persisted for weapon 6
SELECT * FROM Maintenance WHERE weapon_id = 6;


-- ----------------------------------------------------------------------------
-- STEP 10: DATA CONTROL LANGUAGE (DCL) - ACCESS CONTROL & SECURITY
-- ----------------------------------------------------------------------------

-- Create dedicated armory database users
CREATE USER IF NOT EXISTS 'armory_supervisor'@'localhost' IDENTIFIED BY 'SuperSecureArmory#2026';
CREATE USER IF NOT EXISTS 'duty_officer'@'localhost' IDENTIFIED BY 'DutyPass#2026';
CREATE USER IF NOT EXISTS 'external_auditor'@'localhost' IDENTIFIED BY 'AuditViewOnly#2026';

-- 1. Grant Full Privileges on weapon_management_db to Armory Supervisor
GRANT ALL PRIVILEGES ON weapon_management_db.* TO 'armory_supervisor'@'localhost' WITH GRANT OPTION;

-- 2. Grant Operational Privileges (Issue/Return/View) to Duty Officer
GRANT SELECT, INSERT, UPDATE ON weapon_management_db.Weapon_Allocation TO 'duty_officer'@'localhost';
GRANT SELECT, UPDATE ON weapon_management_db.Weapon TO 'duty_officer'@'localhost';
GRANT SELECT ON weapon_management_db.Personnel TO 'duty_officer'@'localhost';
GRANT SELECT ON weapon_management_db.Category TO 'duty_officer'@'localhost';
GRANT SELECT ON weapon_management_db.Storage TO 'duty_officer'@'localhost';
GRANT SELECT ON weapon_management_db.vw_active_allocations TO 'duty_officer'@'localhost';
GRANT SELECT ON weapon_management_db.vw_overdue_allocations TO 'duty_officer'@'localhost';
GRANT EXECUTE ON PROCEDURE weapon_management_db.sp_issue_weapon TO 'duty_officer'@'localhost';
GRANT EXECUTE ON PROCEDURE weapon_management_db.sp_return_weapon TO 'duty_officer'@'localhost';

-- 3. Grant Read-Only Audit Privileges to External Auditor
GRANT SELECT ON weapon_management_db.vw_weapon_inventory_summary TO 'external_auditor'@'localhost';
GRANT SELECT ON weapon_management_db.vw_overdue_allocations TO 'external_auditor'@'localhost';
GRANT SELECT ON weapon_management_db.Allocation_Audit_Log TO 'external_auditor'@'localhost';

-- Revoke specific sensitive privileges to demonstrate Revocation
REVOKE DROP, ALTER ON weapon_management_db.* FROM 'duty_officer'@'localhost';

-- Apply privilege tables
FLUSH PRIVILEGES;

-- ============================================================================
-- END OF WEAPON MANAGEMENT SYSTEM SQL SCRIPT
-- ============================================================================
