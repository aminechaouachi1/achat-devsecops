package tn.esprit.achat.controllers;

import jakarta.validation.Valid;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import tn.esprit.achat.entities.Produit;
import tn.esprit.achat.services.ProduitService;

@RestController
@RequestMapping("/produits")
public class ProduitController {

    private final ProduitService service;

    public ProduitController(ProduitService service) {
        this.service = service;
    }

    @GetMapping
    public List<Produit> all() {
        return service.findAll();
    }

    @GetMapping("/{id}")
    public Produit one(@PathVariable Long id) {
        return service.findById(id);
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Produit create(@Valid @RequestBody Produit produit) {
        return service.create(produit);
    }

    @PutMapping("/{id}")
    public Produit update(@PathVariable Long id, @Valid @RequestBody Produit produit) {
        return service.update(id, produit);
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable Long id) {
        service.delete(id);
    }
}
