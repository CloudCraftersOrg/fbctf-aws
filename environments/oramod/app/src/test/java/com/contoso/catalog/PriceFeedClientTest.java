package com.contoso.catalog;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.springframework.test.context.junit4.SpringRunner;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

// JUnit 4 (@RunWith / org.junit.Test) - Transform's Java agent moves this to
// JUnit 5 (@ExtendWith(SpringExtension.class), org.junit.jupiter.api.Test).
@RunWith(SpringRunner.class)
public class PriceFeedClientTest {

    @Test
    public void labelHasPrefix() {
        assertTrue(new PriceFeedClient().lastCheckedLabel().startsWith("price feed checked "));
    }

    @Test
    public void unreachableFeedIsFalse() {
        assertFalse(new PriceFeedClient().feedReachable("http://127.0.0.1:9/none"));
    }
}
