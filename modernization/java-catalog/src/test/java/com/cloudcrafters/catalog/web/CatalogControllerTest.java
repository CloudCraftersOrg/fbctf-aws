package com.cloudcrafters.catalog.web;

import com.cloudcrafters.catalog.domain.Challenge;
import com.cloudcrafters.catalog.domain.ChallengeRepository;
import com.cloudcrafters.catalog.service.ScoreClient;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.mockito.Mock;
import org.mockito.junit.MockitoJUnitRunner;

import java.util.Arrays;
import java.util.Map;

import static org.junit.Assert.assertEquals;
import static org.mockito.Mockito.when;

@RunWith(MockitoJUnitRunner.class)
public class CatalogControllerTest {

    @Mock
    private ChallengeRepository repository;

    @Mock
    private ScoreClient scoreClient;

    private CatalogController controller;

    @Before
    public void setUp() {
        controller = new CatalogController(repository, scoreClient);
    }

    @Test
    public void summaryCombinesScoreAndOpenCount() {
        when(scoreClient.currentScore(7L)).thenReturn(420);
        when(scoreClient.lastSyncLabel()).thenReturn("2026-09-01T00:00:00Z");
        when(repository.findByActiveTrueOrderByPointsDesc())
                .thenReturn(Arrays.asList(new Challenge(), new Challenge()));

        Map<String, Object> out = controller.summary(7L);

        assertEquals(420, out.get("score"));
        assertEquals(2, out.get("openChallenges"));
        assertEquals("2026-09-01T00:00:00Z", out.get("asOf"));
    }
}
