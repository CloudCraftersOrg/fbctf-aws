package com.cloudcrafters.catalog.service;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.text.SimpleDateFormat;
import java.util.Date;

@Service
public class ScoreClient {

    private final RestTemplate rest = new RestTemplate();
    private final SimpleDateFormat stamp = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'");

    @Value("${scoring.base-url:http://contoso-app-01.corp.local/ScoringService.svc}")
    private String baseUrl;

    public int currentScore(long teamId) {
        String url = baseUrl + "/rest/score/" + teamId;
        Integer score = rest.getForObject(url, Integer.class);
        return score == null ? 0 : score;
    }

    public String lastSyncLabel() {
        return stamp.format(new Date());
    }
}
