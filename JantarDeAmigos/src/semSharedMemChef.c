/**
 *  \file semSharedMemChef.c (implementation file)
 *
 *  \brief Problem name: Restaurant
 *
 *  Synchronization based on semaphores and shared memory.
 *  Implementation with SVIPC.
 *
 *  Definition of the operations carried out by the chef:
 *     \li waitOrder
 *     \li processOrder
 *
 *  \author Nuno Lau - December 2022
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <unistd.h>
#include <sys/types.h>
#include <string.h>
#include <math.h>
#include <signal.h>
#include <sys/time.h>
#include <errno.h>

#include "probConst.h"
#include "probDataStruct.h"
#include "logging.h"
#include "sharedDataSync.h"
#include "semaphore.h"
#include "sharedMemory.h"


/** \brief logging file name */
static char nFic[51];

/** \brief shared memory block access identifier */
static int shmid;

/** \brief semaphore set access identifier */
static int semgid;

/** \brief pointer to shared memory region */
static SHARED_DATA *sh;

static void waitForOrder ();
static void processOrder ();

/**
 *  \brief Main program.
 *
 *  Its role is to generate the life cycle of one of intervening entities in the problem: the chef.
 */
int main (int argc, char *argv[])
{
    int key;                                          /*access key to shared memory and semaphore set */
    char *tinp;                                                     /* numerical parameters test flag */

    /* validation of command line parameters */

    if (argc != 4) { 
        freopen ("error_PT", "a", stderr);
        fprintf (stderr, "Number of parameters is incorrect!\n");
        return EXIT_FAILURE;
    }
    else {
       freopen (argv[3], "w", stderr);
       setbuf(stderr,NULL);
    }
    strcpy (nFic, argv[1]);
    key = (unsigned int) strtol (argv[2], &tinp, 0);
    if (*tinp != '\0') {
        fprintf (stderr, "Error on the access key communication!\n");
        return EXIT_FAILURE;
    }

    /* connection to the semaphore set and the shared memory region and mapping the shared region onto the
       process address space */
    if ((semgid = semConnect (key)) == -1) { 
        perror ("error on connecting to the semaphore set");
        return EXIT_FAILURE;
    }
    if ((shmid = shmemConnect (key)) == -1) { 
        perror ("error on connecting to the shared memory region");
        return EXIT_FAILURE;
    }
    if (shmemAttach (shmid, (void **) &sh) == -1) { 
        perror ("error on mapping the shared region on the process address space");
        return EXIT_FAILURE;
    }

    /* initialize random generator */
    srandom ((unsigned int) getpid ());                                      

    /* simulation of the life cycle of the chef */

    waitForOrder();
    processOrder();

    /* unmapping the shared region off the process address space */

    if (shmemDettach (sh) == -1) { 
        perror ("error on unmapping the shared region off the process address space");
        return EXIT_FAILURE;;
    }

    return EXIT_SUCCESS;
}

/**
 *  \brief chefs wait for a food order.
 *
 *  The chef waits for the food request that will be provided by the waiter.
 */
static void waitForOrder ()
{
    /* enter critical region */
    if (semDown (semgid, sh->mutex) == -1) {                            
        perror ("error on the down operation for semaphore access (PT)");
        exit (EXIT_FAILURE);
    }

    /* Update its state */
    sh->fSt.st.chefStat = WAIT_FOR_ORDER;

    /* exit critical region */
    if (semUp (semgid, sh->mutex) == -1) {                              
        perror ("error on the up operation for semaphore access (PT)");
        exit (EXIT_FAILURE);
    }

    /* Wait for an order to be recieved */
    if (semDown (semgid, sh->waitOrder) == -1) {                                       
        perror ("error on the down operation for 'waitOrder' semaphore access (PT)");
        exit (EXIT_FAILURE);
    }
}

/**
 *  \brief chef cooks, then delivers the food to the waiter and then rests 
 *
 *  The chef updates its state and signals the waiter that food is ready
 *  The internal state should be saved.
 */
static void processOrder ()
{               
    /* enter critical region */
    if (semDown (semgid, sh->mutex) == -1) {              
        perror ("error on the down operation for semaphore access (PT)");
        exit (EXIT_FAILURE);
    }

    /* Update its state */
    sh->fSt.st.chefStat = COOK;
    sh->fSt.foodReady = true;
    saveState(nFic, &(sh->fSt));

    /* exit critical region */
    if (semUp (semgid, sh->mutex) == -1) {       
        perror ("error on the up operation for semaphore access (PT)");
        exit (EXIT_FAILURE);
    }

    usleep((unsigned int) floor ((MAXCOOK * random ()) / RAND_MAX + 100.0));

    /* enter critical region */
    if (semDown (semgid, sh->mutex) == -1) {                                 
        perror ("error on the down operation for semaphore access (PT)");
        exit (EXIT_FAILURE);
    }

    /* Update its state */
    sh->fSt.st.chefStat = REST;
    saveState(nFic, &(sh->fSt));

    /* exit critical region */
    if (semUp (semgid, sh->mutex) == -1) {                
        perror ("error on the up operation for semaphore access (PT)");
        exit (EXIT_FAILURE);
    }

    /* Signal the waiter that the cook is finished */
    if (semUp (semgid, sh->waiterRequest) == -1) {
        perror ("error on the up operation for 'waiterRequest' semaphore access (PT)");
        exit (EXIT_FAILURE);
    }

    /* Wait for waiter to confirm request */
    if (semDown (semgid, sh->requestReceived) == -1) {      
        perror ("error on the down operation for 'requestReceived' semaphore access (PT)");
        exit (EXIT_FAILURE);
    }
}

