-- Stand-in for a prepared dump. A real project restores its own here.
CREATE TABLE greeting (id serial PRIMARY KEY, text text NOT NULL);
INSERT INTO greeting (text) VALUES ('hello from the seed');
