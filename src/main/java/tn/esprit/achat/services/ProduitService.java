package tn.esprit.achat.services;

import java.util.List;
import java.util.NoSuchElementException;
import org.springframework.stereotype.Service;
import tn.esprit.achat.entities.Produit;
import tn.esprit.achat.repositories.ProduitRepository;

@Service
public class ProduitService {

    private final ProduitRepository repository;

    public ProduitService(ProduitRepository repository) {
        this.repository = repository;
    }

    public List<Produit> findAll() {
        return repository.findAll();
    }

    public Produit findById(Long id) {
        return repository.findById(id)
                .orElseThrow(() -> new NoSuchElementException("Produit introuvable : " + id));
    }

    public Produit create(Produit produit) {
        produit.setId(null);
        return repository.save(produit);
    }

    public Produit update(Long id, Produit data) {
        Produit existant = findById(id);
        existant.setCode(data.getCode());
        existant.setLibelle(data.getLibelle());
        existant.setPrix(data.getPrix());
        existant.setStock(data.getStock());
        return repository.save(existant);
    }

    public void delete(Long id) {
        repository.delete(findById(id));
    }
}
