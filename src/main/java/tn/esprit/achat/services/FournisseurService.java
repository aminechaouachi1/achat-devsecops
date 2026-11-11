package tn.esprit.achat.services;

import java.util.List;
import java.util.NoSuchElementException;
import org.springframework.stereotype.Service;
import tn.esprit.achat.entities.Fournisseur;
import tn.esprit.achat.repositories.FournisseurRepository;

@Service
public class FournisseurService {

    private final FournisseurRepository repository;

    public FournisseurService(FournisseurRepository repository) {
        this.repository = repository;
    }

    public List<Fournisseur> findAll() {
        return repository.findAll();
    }

    public Fournisseur findById(Long id) {
        return repository.findById(id)
                .orElseThrow(() -> new NoSuchElementException("Fournisseur introuvable : " + id));
    }

    public Fournisseur create(Fournisseur fournisseur) {
        fournisseur.setId(null);
        return repository.save(fournisseur);
    }

    public void delete(Long id) {
        repository.delete(findById(id));
    }
}
