package com.cloudcrafters.catalog.domain;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;

public interface ChallengeRepository extends JpaRepository<Challenge, Long> {

    List<Challenge> findByActiveTrueOrderByPointsDesc();

    @Query("select c from Challenge c where c.category = :cat and c.active = true")
    List<Challenge> activeInCategory(@Param("cat") String category);
}
