package tn.esprit.achat.repositories;

import org.springframework.data.jpa.repository.JpaRepository;
import tn.esprit.achat.entities.Fournisseur;

public interface FournisseurRepository extends JpaRepository<Fournisseur, Long> { }
