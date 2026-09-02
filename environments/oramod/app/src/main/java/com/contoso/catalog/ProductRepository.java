package com.contoso.catalog;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;

public interface ProductRepository extends JpaRepository<Product, Long> {

    List<Product> findAllByOrderByCategoryAscNameAsc();

    // Native Oracle query against the PL/SQL-maintained summary view.
    @Query(value = "SELECT category, product_count, total_stock, avg_price "
            + "FROM VW_CATALOG_SUMMARY ORDER BY category", nativeQuery = true)
    List<Object[]> summaryByCategory();

    @Query(value = "SELECT catalog_pkg.restock(:sku, :qty) FROM dual", nativeQuery = true)
    int restock(@Param("sku") String sku, @Param("qty") int qty);
}
