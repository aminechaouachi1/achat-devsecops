package tn.esprit.achat.controllers;

import jakarta.validation.Valid;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import tn.esprit.achat.entities.Fournisseur;
import tn.esprit.achat.services.FournisseurService;

@RestController
@RequestMapping("/fournisseurs")
public class FournisseurController {

    private final FournisseurService service;

    public FournisseurController(FournisseurService service) {
        this.service = service;
    }

    @GetMapping
    public List<Fournisseur> all() {
        return service.findAll();
    }

    @GetMapping("/{id}")
    public Fournisseur one(@PathVariable Long id) {
        return service.findById(id);
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Fournisseur create(@Valid @RequestBody Fournisseur fournisseur) {
        return service.create(fournisseur);
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable Long id) {
        service.delete(id);
    }
}
