.print "Creating SAMPLEDB schema objects..."

-- parent table
CREATE TABLE IF NOT EXISTS parent
(
    uid INTEGER PRIMARY KEY,
    parent_name TEXT NOT NULL
);

-- child table
CREATE TABLE IF NOT EXISTS child
(
    parent_uid INTEGER NOT NULL,
    child_name TEXT NOT NULL,
    FOREIGN KEY(parent_uid)
        REFERENCES parent(uid)
        ON UPDATE CASCADE
        ON DELETE CASCADE
);