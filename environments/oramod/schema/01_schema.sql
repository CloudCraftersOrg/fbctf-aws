-- Contoso Catalog OLTP schema - Oracle Database 21c. Source for AWS Transform /
-- DMS + SCT heterogeneous conversion to Aurora PostgreSQL. Deliberately uses
-- Oracle idioms that force a real conversion: SEQUENCE + BEFORE-INSERT trigger
-- for the surrogate key, a virtual column, a PL/SQL package, and DUAL.

CREATE TABLE products (
    id          NUMBER(12)      NOT NULL,
    sku         VARCHAR2(32)    NOT NULL,
    name        VARCHAR2(120)   NOT NULL,
    category    VARCHAR2(40),
    price       NUMBER(10,2)    NOT NULL,
    stock       NUMBER(9)       DEFAULT 0 NOT NULL,
    low_stock   VARCHAR2(3)     GENERATED ALWAYS AS (CASE WHEN stock < 10 THEN 'yes' ELSE 'no' END) VIRTUAL,
    created_at  TIMESTAMP       DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_products PRIMARY KEY (id),
    CONSTRAINT uq_products_sku UNIQUE (sku),
    CONSTRAINT ck_products_price CHECK (price >= 0)
);

CREATE SEQUENCE product_seq START WITH 1 INCREMENT BY 1 NOCACHE;

CREATE OR REPLACE TRIGGER trg_products_bi
BEFORE INSERT ON products
FOR EACH ROW
WHEN (new.id IS NULL)
BEGIN
    :new.id := product_seq.NEXTVAL;
END;
/

CREATE OR REPLACE VIEW vw_catalog_summary AS
SELECT category,
       COUNT(*)                       AS product_count,
       NVL(SUM(stock), 0)             AS total_stock,
       ROUND(AVG(price), 2)           AS avg_price
FROM   products
GROUP  BY category;

CREATE OR REPLACE PACKAGE catalog_pkg AS
    -- Adds qty to a SKU's stock and returns the new level, or -1 if the SKU
    -- does not exist. Called from the app as: SELECT catalog_pkg.restock(?,?) FROM dual
    FUNCTION restock(p_sku IN VARCHAR2, p_qty IN NUMBER) RETURN NUMBER;
END catalog_pkg;
/

CREATE OR REPLACE PACKAGE BODY catalog_pkg AS
    FUNCTION restock(p_sku IN VARCHAR2, p_qty IN NUMBER) RETURN NUMBER IS
        v_new products.stock%TYPE;
    BEGIN
        UPDATE products
        SET    stock = stock + p_qty
        WHERE  sku = p_sku
        RETURNING stock INTO v_new;

        IF SQL%ROWCOUNT = 0 THEN
            RETURN -1;
        END IF;

        COMMIT;
        RETURN v_new;
    END restock;
END catalog_pkg;
/
