package br.ufsc.atividade11;

import java.util.*;
import java.util.concurrent.locks.Condition;
import java.util.concurrent.locks.ReentrantLock;

import javax.annotation.Nonnull;
import java.util.concurrent.locks.ReentrantReadWriteLock;

public class Market {
    private Map<Product, Double> prices = new HashMap<>();

    private ArrayList<ReentrantReadWriteLock> locks = new ArrayList<ReentrantReadWriteLock>();
    private ArrayList<ReentrantLock> rlocks = new ArrayList<ReentrantLock>();
    private Condition[] conditions = new Condition[9];
    
    public Market() {
        for (Product product : Product.values()) {
            try {
            	locks.add(new ReentrantReadWriteLock());
            	rlocks.add(new ReentrantLock());
            	conditions[product.ordinal()] = rlocks.get(product.ordinal()).newCondition();
                
                locks.get(product.ordinal()).writeLock().lock();
                prices.put(product, 1.99);
            } finally {
            	locks.get(product.ordinal()).writeLock().unlock();
            }
        }
    }
    
    // Atribui um preço a um produto específico
    public void setPrice(@Nonnull Product product, double value) {			
    	
    	if(rlocks.get(product.ordinal()).tryLock()) {
	    	locks.get(product.ordinal()).writeLock().lock();
	    	try {
	            prices.put(product, value);
	            conditions[product.ordinal()].signal();
	        } finally {
	            locks.get(product.ordinal()).writeLock().unlock();
	        }
	    	rlocks.get(product.ordinal()).unlock();
    	}
    }

    // Pega um produto da gôndola e coloca na cesta. 
    // O retorno é o valor do produto
    public double take(@Nonnull Product product) {
        locks.get(product.ordinal()).readLock().lock();
        return prices.get(product);
    }
    
    // Tira um produto da cesta e coloca de volta na gôndola
    public void putBack(@Nonnull Product product) {
        locks.get(product.ordinal()).readLock().unlock();
    }
     
    // Espera até que o preço do produto baixe para um valor 
    // menor que maximumValue. Quando isso acontecer, coloca 
    // o produto na cesta. O método retorna o valor do produto 
    // colocado na cesta
    public double waitForOffer(@Nonnull Product product,
                               double maximumValue) throws InterruptedException {
//        locks.get(product.ordinal()).writeLock().lock();

    	//deveria esperar até que prices.get(product) <= maximumValue
//        System.out.println(prices.get(product) + " > " + maximumValue);
        while(prices.get(product) > maximumValue) {
            conditions[product.ordinal()].await();
        }
        
        locks.get(product.ordinal()).writeLock().unlock();
        locks.get(product.ordinal()).readLock().lock();

        return prices.get(product);
    }
    
    // Paga por um produto. O retorno é o valor pago, que deve 
    // ser o mesmo retornado por waitForOffer() ou take()
    public double pay(@Nonnull Product product) {
        locks.get(product.ordinal()).readLock().unlock();
        return prices.get(product);
    }
}
