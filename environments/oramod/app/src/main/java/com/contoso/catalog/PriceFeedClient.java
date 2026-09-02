package com.contoso.catalog;

import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;

import java.text.SimpleDateFormat;
import java.util.Date;

// RestTemplate is in maintenance mode (Transform flags it for WebClient /
// RestClient); SimpleDateFormat is not thread-safe as a field (flagged for
// java.time). Both are here on purpose as Java-modernization targets.
@Component
public class PriceFeedClient {

    private final RestTemplate rest = new RestTemplate();
    private final SimpleDateFormat stamp = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss");

    public String lastCheckedLabel() {
        return "price feed checked " + stamp.format(new Date());
    }

    public boolean feedReachable(String url) {
        try {
            rest.headForHeaders(url);
            return true;
        } catch (Exception e) {
            return false;
        }
    }
}
