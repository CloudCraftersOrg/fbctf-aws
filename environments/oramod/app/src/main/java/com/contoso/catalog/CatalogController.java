package com.contoso.catalog;

import org.springframework.stereotype.Controller;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.servlet.mvc.support.RedirectAttributes;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

@Controller
public class CatalogController {

    private final ProductRepository repo;

    public CatalogController(ProductRepository repo) {
        this.repo = repo;
    }

    @GetMapping("/")
    public String index(Model model) {
        model.addAttribute("products", repo.findAllByOrderByCategoryAscNameAsc());
        List<Map<String, Object>> rows = new ArrayList<>();
        for (Object[] r : repo.summaryByCategory()) {
            Map<String, Object> m = new java.util.LinkedHashMap<>();
            m.put("category", r[0]);
            m.put("count", r[1]);
            m.put("stock", r[2]);
            m.put("avgPrice", r[3]);
            rows.add(m);
        }
        model.addAttribute("summary", rows);
        return "index";
    }

    @PostMapping("/products")
    public String add(@RequestParam String sku, @RequestParam String name,
                      @RequestParam String category, @RequestParam BigDecimal price,
                      @RequestParam(defaultValue = "0") int stock, RedirectAttributes ra) {
        Product p = new Product();
        p.setSku(sku.trim());
        p.setName(name.trim());
        p.setCategory(category.trim());
        p.setPrice(price);
        p.setStock(stock);
        repo.save(p);
        ra.addFlashAttribute("msg", "Added " + p.getSku());
        return "redirect:/";
    }

    @PostMapping("/restock")
    @Transactional
    public String restock(@RequestParam String sku, @RequestParam int qty, RedirectAttributes ra) {
        int newStock = repo.restock(sku.trim(), qty);
        ra.addFlashAttribute("msg", newStock < 0
                ? "Unknown SKU " + sku
                : sku + " restocked to " + newStock);
        return "redirect:/";
    }

    @GetMapping("/api/products")
    @ResponseBody
    public List<Product> apiProducts() {
        return repo.findAll();
    }
}
