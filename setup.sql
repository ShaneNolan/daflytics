use rentServerlessMysql;
CREATE TABLE IF NOT EXISTS property (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    title TEXT NOT NULL,
    price INT NOT NULL,
    propertyType TEXT,
    numBedrooms TEXT,
    numBathrooms TEXT,
    ber TEXT,
    facilities TEXT,
    propertyOverview TEXT,
    timestampExtracted TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);