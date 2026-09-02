package com.cloudcrafters.catalog.web;

import com.cloudcrafters.catalog.domain.Challenge;
import com.cloudcrafters.catalog.domain.ChallengeRepository;
import com.cloudcrafters.catalog.service.ScoreClient;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/challenges")
public class CatalogController {

    private final ChallengeRepository repository;
    private final ScoreClient scoreClient;

    public CatalogController(ChallengeRepository repository, ScoreClient scoreClient) {
        this.repository = repository;
        this.scoreClient = scoreClient;
    }

    @GetMapping
    public List<Challenge> list(@RequestParam(required = false) String category) {
        if (category != null) {
            return repository.activeInCategory(category);
        }
        return repository.findByActiveTrueOrderByPointsDesc();
    }

    @GetMapping("/{id}")
    public ResponseEntity<Challenge> byId(@PathVariable Long id) {
        return repository.findById(id)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    @GetMapping("/team/{teamId}/summary")
    public Map<String, Object> summary(@PathVariable long teamId) {
        Map<String, Object> out = new HashMap<>();
        out.put("teamId", teamId);
        out.put("score", scoreClient.currentScore(teamId));
        out.put("openChallenges", repository.findByActiveTrueOrderByPointsDesc().size());
        out.put("asOf", scoreClient.lastSyncLabel());
        return out;
    }
}
